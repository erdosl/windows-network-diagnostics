using System;
using System.Collections.Generic;
using System.IO;
using System.Text;
namespace NetworkDiagnostics {
    // Deliberately restricted offline decoder: little-endian pcapng 1.0, Ethernet,
    // EPB timestamps in micro/nanoseconds, unfragmented IPv4 UDP DHCP and Ethernet ARP.
    public static class CaptureDecoder {
        static ushort LE16(byte[] b,int p) { return BitConverter.ToUInt16(b,p); }
        static uint LE32(byte[] b,int p) { return BitConverter.ToUInt32(b,p); }
        static ushort BE16(byte[] b,int p) { return (ushort)((b[p]<<8)|b[p+1]); }
        static uint BE32(byte[] b,int p) { return ((uint)b[p]<<24)|((uint)b[p+1]<<16)|((uint)b[p+2]<<8)|b[p+3]; }
        static string Hex(byte[] b,int p,int n) { return BitConverter.ToString(b,p,n).Replace("-",""); }
        static string IP(byte[] b,int p) { return b[p]+"."+b[p+1]+"."+b[p+2]+"."+b[p+3]; }
        static Dictionary<string,object> Obj() { return new Dictionary<string,object>(); }
        public static object Decode(string path,int maxPackets) {
            var output=Obj(); var packets=new List<object>(); var errors=new List<object>();
            output["Packets"]=packets;output["Errors"]=errors;output["Format"]="pcapng little-endian 1.0 Ethernet EPB";
            output["Limitation"]="No reassembly, checksums, ETL decoding or physical topology inference. Unsupported/truncated frames remain referenced by offset. Capture may omit unicast traffic and earlier packets.";
            var links=new List<ushort>();var resolutions=new List<int>();bool section=false;int count=0,sectionId=-1;
            using(var stream=File.OpenRead(path)) using(var reader=new BinaryReader(stream)) {
                if(stream.Length==0)throw new InvalidDataException("Empty capture input; no section header.");
                if(stream.Length>64L*1024*1024) throw new InvalidDataException("Offline input exceeds 64 MiB limit.");
                while(stream.Position<stream.Length && count<maxPackets) {
                    long offset=stream.Position;
                    try {
                        if(stream.Length-offset<12) throw new InvalidDataException("Truncated block header.");
                        uint type=reader.ReadUInt32();uint size=reader.ReadUInt32();
                        if(size<12 || size>1048576 || size%4!=0 || size>stream.Length-offset) throw new InvalidDataException("Invalid, oversized, or truncated block.");
                        byte[] body=reader.ReadBytes((int)size-12);if(reader.ReadUInt32()!=size)throw new InvalidDataException("Block lengths disagree.");
                        if(type==0x0a0d0d0a) {
                            if(body.Length<16 || LE32(body,0)!=0x1a2b3c4d || LE16(body,4)!=1 || LE16(body,6)!=0)throw new InvalidDataException("Unsupported pcapng section byte order/version.");
                            section=true;sectionId++;links.Clear();resolutions.Clear();continue;
                        }
                        if(!section)throw new InvalidDataException("Missing section header.");
                        if(type==1) {
                            if(body.Length<8)throw new InvalidDataException("Truncated interface block.");
                            int resolution=6;
                            for(int pos=8;pos+4<=body.Length;) {
                                ushort code=LE16(body,pos),length=LE16(body,pos+2);pos+=4;
                                if(code==0)break;if(pos+length>body.Length)throw new InvalidDataException("Truncated interface option.");
                                if(code==9){if(length!=1 || (body[pos]!=6 && body[pos]!=9))resolution=-1;else resolution=body[pos];}
                                if(code==14)resolution=-1; // unsupported timestamp offset
                                pos+=(length+3)&~3;
                            }
                            links.Add(LE16(body,0));resolutions.Add(resolution);continue;
                        }
                        if(type!=6) { if(type==2 || type==3)throw new InvalidDataException("Unsupported packet block type.");continue; }
                        count++;
                        if(body.Length<20)throw new InvalidDataException("Truncated enhanced packet block.");
                        uint id=LE32(body,0),captured=LE32(body,12),original=LE32(body,16);
                        if(id>=links.Count || links[(int)id]!=1 || resolutions[(int)id]<0)throw new InvalidDataException("Unsupported interface link type or timestamp resolution.");
                        if(captured>body.Length-20 || captured>original)throw new InvalidDataException("Invalid captured length.");
                        ulong timestamp=((ulong)LE32(body,4)<<32)|LE32(body,8);
                        double seconds=timestamp/(resolutions[(int)id]==6?1e6:1e9);
                        string time=new DateTimeOffset(1970,1,1,0,0,0,TimeSpan.Zero).AddSeconds(seconds).ToString("o");
                        byte[] frame=new byte[captured];Array.Copy(body,20,frame,0,(int)captured);
                        var packet=Frame(frame);if(packet==null)continue;
                        packet["Timestamp"]=time;packet["SectionId"]=sectionId;packet["InterfaceId"]=id;packet["BlockOffset"]=offset;
                        packet["CapturedLength"]=captured;packet["OriginalLength"]=original;packet["Truncated"]=captured<original;
                        packets.Add(packet);
                    } catch(Exception ex) {
                        var error=Obj();error["BlockOffset"]=offset;error["Message"]=ex.Message;errors.Add(error);
                        // Structural errors stop parsing; never scan for magic bytes in payload.
                        break;
                    }
                }
                output["PacketLimitReached"]=count>=maxPackets && stream.Position<stream.Length;
            }
            output["Status"]=errors.Count==0?"Decoded":"PartialOrUnsupported";return output;
        }
        static Dictionary<string,object> Frame(byte[] b) {
            if(b.Length<14)throw new InvalidDataException("Truncated Ethernet header.");
            int p=14;ushort type=BE16(b,12);
            for(int vlan=0;type==0x8100 || type==0x88a8;vlan++) {
                if(vlan>=2 || b.Length<p+4)throw new InvalidDataException("Unsupported/truncated VLAN header.");
                type=BE16(b,p+2);p+=4;
            }
            var row=Obj();row["EthernetSource"]=Hex(b,6,6);row["EthernetDestination"]=Hex(b,0,6);
            if(type==0x806) {
                if(b.Length<p+28 || BE16(b,p)!=1 || BE16(b,p+2)!=0x800 || b[p+4]!=6 || b[p+5]!=4)throw new InvalidDataException("Unsupported/truncated ARP packet.");
                row["Kind"]="ARP";row["Operation"]=BE16(b,p+6);row["SenderHardwareAddress"]=Hex(b,p+8,6);row["SenderProtocolAddress"]=IP(b,p+14);
                row["TargetHardwareAddress"]=Hex(b,p+18,6);row["TargetProtocolAddress"]=IP(b,p+24);return row;
            }
            if(type!=0x800)return null;
            if(b.Length<p+20 || b[p]>>4!=4)throw new InvalidDataException("Invalid IPv4 header.");
            int ihl=(b[p]&15)*4,total=BE16(b,p+2);if(ihl<20 || total<ihl || b.Length<p+total)throw new InvalidDataException("Truncated IPv4 packet.");
            if(b[p+9]!=17)return null;
            if((BE16(b,p+6)&0x3fff)!=0)throw new InvalidDataException("Fragment reassembly unsupported.");
            int udp=p+ihl;if(udp+8>p+total)throw new InvalidDataException("Truncated UDP header.");
            ushort source=BE16(b,udp),dest=BE16(b,udp+2),length=BE16(b,udp+4);
            if(source!=67 && source!=68 && dest!=67 && dest!=68)return null;
            if(length<248 || udp+length>p+total)throw new InvalidDataException("Truncated DHCP datagram.");
            int d=udp+8,end=udp+length;if(BE32(b,d+236)!=0x63825363)throw new InvalidDataException("Not DHCP magic cookie.");
            if(b[d+2]>16)throw new InvalidDataException("Invalid client hardware length.");
            row["Kind"]="DHCPv4";row["PacketSource"]=IP(b,p+12);row["PacketDestination"]=IP(b,p+16);
            row["TransactionId"]=BE32(b,d+4).ToString("X8");row["ClientHardwareType"]=b[d+1];row["ClientHardwareAddress"]=Hex(b,d+28,b[d+2]);
            row["ClientAddress"]=IP(b,d+12);row["OfferedAddress"]=IP(b,d+16);row["RelayAddress"]=IP(b,d+24);
            row["ClientIdentifier"]=null;row["MessageType"]=null;row["ServerIdentifier"]=null;row["RequestedAddress"]=null;
            var options=new List<object>();row["Options"]=options;var seen=new HashSet<int>();bool terminated=false;
            for(int o=d+240;o<end;) {
                int code=b[o++];if(code==255){terminated=true;break;}if(code==0)continue;
                if(o>=end)throw new InvalidDataException("Missing DHCP option length.");int len=b[o++];
                if(o+len>end)throw new InvalidDataException("Truncated DHCP option.");
                var option=Obj();option["Code"]=code;option["Hex"]=Hex(b,o,len);options.Add(option);
                if(!seen.Add(code))throw new InvalidDataException("Repeated DHCP option unsupported; raw packet retained.");
                if(code==52)throw new InvalidDataException("DHCP option overload unsupported; raw packet retained.");
                if(code==53){if(len!=1)throw new InvalidDataException("Invalid DHCP type.");row["MessageType"]=b[o];}
                if(code==61)row["ClientIdentifier"]=Hex(b,o,len);
                if(code==50 || code==54){if(len!=4)throw new InvalidDataException("Invalid DHCP address option.");row[code==50?"RequestedAddress":"ServerIdentifier"]=IP(b,o);}
                if(code==3 || code==6){if(len==0 || len%4!=0)throw new InvalidDataException("Invalid DHCP address list.");var values=new List<string>();for(int i=0;i<len;i+=4)values.Add(IP(b,o+i));row[code==3?"Gateways":"DnsServers"]=values;}
                if(code==15)row["Domain"]=Encoding.ASCII.GetString(b,o,len);
                if(code==51 || code==58 || code==59){if(len!=4)throw new InvalidDataException("Invalid DHCP duration.");row[code==51?"LeaseSeconds":code==58?"T1Seconds":"T2Seconds"]=BE32(b,o);}
                o+=len;
            }
            if(!terminated)throw new InvalidDataException("Missing DHCP end option.");return row;
        }
    }
}
