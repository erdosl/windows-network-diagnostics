function New-TestWorkRoot {
    # Synthetic artifacts remain under output/tests, outside a potentially long
    # checkout. Keep the full GUID; never reuse or delete another test's output.
    $base = Join-Path ([IO.Path]::GetTempPath()) 'output\tests'
    $path = Join-Path $base ([guid]::NewGuid().ToString('N'))
    $null = New-Item -ItemType Directory -Path $path -Force -ErrorAction Stop
    $path
}
