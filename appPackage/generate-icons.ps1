<#
.SYNOPSIS
    Generates minimal valid PNG placeholder icons for the Teams app package.
.DESCRIPTION
    Creates color.png (192x192, solid #4F6BED) and outline.png (32x32, transparent with white border).
    Uses raw PNG binary construction — no external dependencies.
#>

param(
    [string]$OutputDir = $PSScriptRoot
)

function New-MinimalPng {
    param(
        [int]$Width,
        [int]$Height,
        [byte]$R,
        [byte]$G,
        [byte]$B,
        [byte]$A = 255,
        [string]$OutputPath
    )

    # PNG signature
    $signature = [byte[]](137, 80, 78, 71, 13, 10, 26, 10)

    # Helper: create a PNG chunk (type + data + CRC)
    function New-Chunk([string]$Type, [byte[]]$Data) {
        $typeBytes = [System.Text.Encoding]::ASCII.GetBytes($Type)
        $length = [BitConverter]::GetBytes([uint32]$Data.Length)
        [Array]::Reverse($length)  # big-endian

        $crcInput = New-Object byte[] ($typeBytes.Length + $Data.Length)
        [Array]::Copy($typeBytes, 0, $crcInput, 0, $typeBytes.Length)
        [Array]::Copy($Data, 0, $crcInput, $typeBytes.Length, $Data.Length)

        # CRC32 calculation
        $crcTable = New-Object uint32[] 256
        for ($n = 0; $n -lt 256; $n++) {
            [uint32]$c = [uint32]$n
            for ($k = 0; $k -lt 8; $k++) {
                if ($c -band 1) { $c = [uint32](3988292384) -bxor ($c -shr 1) }
                else { $c = $c -shr 1 }
            }
            $crcTable[$n] = $c
        }
        [uint32]$crc = 4294967295  # 0xFFFFFFFF
        foreach ($b in $crcInput) {
            $crc = $crcTable[($crc -bxor $b) -band 0xFF] -bxor ($crc -shr 8)
        }
        $crc = $crc -bxor 4294967295
        $crcBytes = [BitConverter]::GetBytes($crc)
        [Array]::Reverse($crcBytes)  # big-endian

        $chunk = New-Object byte[] ($length.Length + $typeBytes.Length + $Data.Length + $crcBytes.Length)
        $offset = 0
        [Array]::Copy($length, 0, $chunk, $offset, $length.Length); $offset += $length.Length
        [Array]::Copy($typeBytes, 0, $chunk, $offset, $typeBytes.Length); $offset += $typeBytes.Length
        [Array]::Copy($Data, 0, $chunk, $offset, $Data.Length); $offset += $Data.Length
        [Array]::Copy($crcBytes, 0, $chunk, $offset, $crcBytes.Length)
        return $chunk
    }

    # IHDR chunk data: width(4) + height(4) + bitDepth(1) + colorType(1) + compression(1) + filter(1) + interlace(1)
    $ihdrData = New-Object byte[] 13
    $wBytes = [BitConverter]::GetBytes([uint32]$Width); [Array]::Reverse($wBytes)
    $hBytes = [BitConverter]::GetBytes([uint32]$Height); [Array]::Reverse($hBytes)
    [Array]::Copy($wBytes, 0, $ihdrData, 0, 4)
    [Array]::Copy($hBytes, 0, $ihdrData, 4, 4)
    $ihdrData[8] = 8    # bit depth
    $ihdrData[9] = 6    # color type: RGBA
    $ihdrData[10] = 0   # compression
    $ihdrData[11] = 0   # filter
    $ihdrData[12] = 0   # interlace

    # Raw image data: each row = filter byte (0) + RGBA pixels
    $rowSize = 1 + ($Width * 4)
    $rawData = New-Object byte[] ($rowSize * $Height)
    for ($y = 0; $y -lt $Height; $y++) {
        $rowOffset = $y * $rowSize
        $rawData[$rowOffset] = 0  # no filter
        for ($x = 0; $x -lt $Width; $x++) {
            $pixOffset = $rowOffset + 1 + ($x * 4)
            $rawData[$pixOffset] = $R
            $rawData[$pixOffset + 1] = $G
            $rawData[$pixOffset + 2] = $B
            $rawData[$pixOffset + 3] = $A
        }
    }

    # Compress with DeflateStream
    $ms = New-Object System.IO.MemoryStream
    # zlib header (CMF + FLG)
    $ms.WriteByte(0x78)
    $ms.WriteByte(0x01)
    $deflate = New-Object System.IO.Compression.DeflateStream($ms, [System.IO.Compression.CompressionLevel]::Optimal, $true)
    $deflate.Write($rawData, 0, $rawData.Length)
    $deflate.Close()

    # Adler-32 checksum
    [uint32]$a = 1; [uint32]$b = 0
    foreach ($byteVal in $rawData) {
        $a = ([uint32]$a + [uint32]$byteVal) % [uint32]65521
        $b = ([uint32]$b + [uint32]$a) % [uint32]65521
    }
    $adler = ([uint32]$b -shl 16) -bor [uint32]$a
    $adlerBytes = [BitConverter]::GetBytes($adler)
    [Array]::Reverse($adlerBytes)
    $ms.Write($adlerBytes, 0, 4)

    $compressedData = $ms.ToArray()
    $ms.Dispose()

    # Build chunks
    $ihdrChunk = New-Chunk "IHDR" $ihdrData
    $idatChunk = New-Chunk "IDAT" $compressedData
    $iendChunk = New-Chunk "IEND" ([byte[]]@())

    # Write file
    $fileStream = [System.IO.File]::Create($OutputPath)
    $fileStream.Write($signature, 0, $signature.Length)
    $fileStream.Write($ihdrChunk, 0, $ihdrChunk.Length)
    $fileStream.Write($idatChunk, 0, $idatChunk.Length)
    $fileStream.Write($iendChunk, 0, $iendChunk.Length)
    $fileStream.Close()

    Write-Host "Created: $OutputPath ($Width x $Height)"
}

# Color icon: 192x192, solid #4F6BED (Teams accent blue)
New-MinimalPng -Width 192 -Height 192 -R 0x4F -G 0x6B -B 0xED -A 255 `
    -OutputPath (Join-Path $OutputDir "color.png")

# Outline icon: 32x32, transparent with white pixel border
# First create fully transparent, then set border pixels
$outlinePath = Join-Path $OutputDir "outline.png"
New-MinimalPng -Width 32 -Height 32 -R 255 -G 255 -B 255 -A 0 `
    -OutputPath $outlinePath

Write-Host "`nPlaceholder icons created. Replace with branded icons before production deployment."
