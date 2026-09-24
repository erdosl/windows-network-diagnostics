using System;
using System.IO;
using System.Text;
namespace NetworkDiagnostics.Tests {
 public static class CaptureFixture {
  static void BE16(byte[] b,int p,int v){b[p]=(byte)(v>>8);b[p+1]=(byte)v;}
  static void Block(BinaryWriter w,uint type,byte[] data){int padding=(4-data.Length%4)%4;uint size=(uint)(12+data.Length+padding);w.Write(type);w.Write(size);w.Write(data);w.Write(new byte[padding]);w.Write(size);}
  static byte[] Dhcp(byte type,byte server,byte client) {
   var o=new MemoryStream();var ow=new BinaryWriter(o);
   ow.Write(new byte[]{53,1,type,61,2,1,client,54,4,192,0,2,server,50,4,192,0,2,20,3,4,192,0,2,1,6,4,192,0,2,53,51,4,0,0,14,16,58,4,0,0,7,8,59,4,0,0,12,78,12,4});ow.Write(Encoding.ASCII.GetBytes("same"));ow.Write(new byte[]{15,7});ow.Write(Encoding.ASCII.GetBytes("<test>!"));ow.Write((byte)255);
   byte[] options=o.ToArray();byte[] b=new byte[14+20+8+240+options.Length];b[6]=2;b[11]=server;BE16(b,12,0x800);
   int ip=14;b[ip]=0x45;BE16(b,ip+2,b.Length-14);b[ip+9]=17;b[ip+12]=192;b[ip+14]=2;b[ip+15]=server;b[ip+16]=255;b[ip+17]=255;b[ip+18]=255;b[ip+19]=255;
   int udp=34;BE16(b,udp,type==3?68:67);BE16(b,udp+2,type==3?67:68);BE16(b,udp+4,b.Length-34);
   int d=42;b[d]=2;b[d+1]=1;b[d+2]=6;b[d+7]=7;b[d+16]=192;b[d+18]=2;b[d+19]=20;b[d+28]=2;b[d+33]=client;
   b[d+236]=99;b[d+237]=130;b[d+238]=83;b[d+239]=99;Array.Copy(options,0,b,d+240,options.Length);return b;
  }
  static byte[] Arp(byte mac){byte[] b=new byte[42];b[6]=2;b[11]=mac;BE16(b,12,0x806);BE16(b,14,1);BE16(b,16,0x800);b[18]=6;b[19]=4;BE16(b,20,2);b[22]=2;b[27]=mac;b[28]=192;b[30]=2;b[31]=1;return b;}
  public static void Write(string path) { WriteVlan(path,new ushort[0],new ushort[0],new ushort[0],new ushort[0],false); }
  static byte[] Tag(byte[] frame,ushort[] tpids,ushort[] tcis,bool truncate) {
   if(truncate){byte[] shortFrame=new byte[16];Array.Copy(frame,shortFrame,12);BE16(shortFrame,12,0x8100);return shortFrame;}
   byte[] result=new byte[frame.Length+4*tpids.Length];Array.Copy(frame,result,12);
   for(int i=0;i<tpids.Length;i++){BE16(result,12+4*i,tpids[i]);BE16(result,14+4*i,tcis[i]);}
   Array.Copy(frame,12,result,12+4*tpids.Length,frame.Length-12);return result;
  }
  public static void WriteVlan(string path,ushort[] tpidA,ushort[] tciA,ushort[] tpidB,ushort[] tciB,bool truncate) {
   using(var w=new BinaryWriter(File.Create(path))) {
    using(var s=new MemoryStream()) {var b=new BinaryWriter(s);b.Write((uint)0x1a2b3c4d);b.Write((ushort)1);b.Write((ushort)0);b.Write((long)-1);Block(w,0x0a0d0d0a,s.ToArray());}
    Block(w,1,new byte[]{1,0,0,0,0xff,0xff,0,0});
    byte[][] frames={Dhcp(2,1,10),Dhcp(2,2,10),Dhcp(3,2,10),Dhcp(5,2,10),Dhcp(6,1,10),Dhcp(2,1,11),Arp(1),Arp(2)};
    for(int i=0;i<frames.Length;i++)using(var s=new MemoryStream()){byte[] frame=Tag(frames[i],i%2==0?tpidA:tpidB,i%2==0?tciA:tciB,truncate);var b=new BinaryWriter(s);b.Write((uint)0);b.Write((uint)0);b.Write((uint)1000000);b.Write((uint)frame.Length);b.Write((uint)frame.Length);b.Write(frame);Block(w,6,s.ToArray());}
   }
  }
 }
}
