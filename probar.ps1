# Pruebas de rodaje-sonidos. Solo necesita Windows PowerShell 5.1.
#   powershell -NoProfile -ExecutionPolicy Bypass -File probar.ps1
# Genera los sonidos dos veces y comprueba: los mismos bytes en las dos corridas; un WAV por elemento del manifiesto y ninguno
# de más; cabecera RIFF/WAVE con PCM de 16 bits, 48 kHz y 1 o 2 canales; la duración de la descripción (±1 ms); pico entre
# −30 y −1 dBFS; sin DC; sin clic al principio ni al final y, en los ambientes, un empalme del bucle como cualquier otra
# muestra. Sale con 0 si todo pasa.
$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

Add-Type -Language CSharp -TypeDefinition @'
using System;
using System.IO;
using System.Text;

public static class WavCheck
{
    // Devuelve "" si pasa o el motivo. ms: duración esperada; loop: ambiente en bucle.
    public static string Check(string path, double ms, bool loop)
    {
        byte[] b = File.ReadAllBytes(path);
        if (b.Length < 44 || Encoding.ASCII.GetString(b, 0, 4) != "RIFF" || Encoding.ASCII.GetString(b, 8, 4) != "WAVE") return "no es RIFF/WAVE";
        if (Encoding.ASCII.GetString(b, 12, 4) != "fmt " || BitConverter.ToInt16(b, 20) != 1) return "no es PCM";
        int ch = BitConverter.ToInt16(b, 22), rate = BitConverter.ToInt32(b, 24), bits = BitConverter.ToInt16(b, 34);
        if (rate != 48000) return "frecuencia " + rate;
        if (bits != 16) return bits + " bits";
        if (ch != 1 && ch != 2) return ch + " canales";
        if (Encoding.ASCII.GetString(b, 36, 4) != "data") return "falta data";
        int data = BitConverter.ToInt32(b, 40);
        if (BitConverter.ToInt32(b, 4) != 36 + data || 44 + data != b.Length) return "tamaños de la cabecera";
        int n = data / (2 * ch);
        double dur = n / 48.0;
        if (Math.Abs(dur - ms) > 1) return string.Format("dura {0:0.0} ms y la descripción dice {1:0.0}", dur, ms);
        double peak = 0;
        for (int c = 0; c < ch; c++)
        {
            double sum = 0, steps = 0;
            var x = new double[n];
            for (int i = 0; i < n; i++) { x[i] = BitConverter.ToInt16(b, 44 + (i * ch + c) * 2) / 32768.0; sum += x[i]; peak = Math.Max(peak, Math.Abs(x[i])); }
            for (int i = 1; i < n; i++) steps += Math.Abs(x[i] - x[i - 1]);
            if (Math.Abs(sum / n) >= 0.001) return string.Format("DC {0:0.0000} en el canal {1}", sum / n, c);
            if (loop)
            {
                double jump = Math.Abs(x[n - 1] - x[0]), limit = Math.Max(0.02, 6 * steps / (n - 1));
                if (jump > limit) return string.Format("el bucle salta {0:0.0000} (límite {1:0.0000})", jump, limit);
            }
            else
            {
                if (Math.Abs(x[0]) > 1 / 256.0 || Math.Abs(x[n - 1]) > 1 / 256.0) return "no empieza o no termina en silencio";
                // 0,25 ms: dentro del fundido, la señal tiene que seguir baja; un clic llegaría arriba de golpe.
                for (int i = 0; i < 12; i++)
                    if (Math.Abs(x[i]) > 0.25 || Math.Abs(x[n - 1 - i]) > 0.25) return "salta en los extremos";
                double e1 = 0;
                for (int i = 0; i < 96; i++) e1 = Math.Max(e1, Math.Abs(x[n - 1 - i]));
                if (e1 > 0.5) return "el final de 2 ms no baja";
            }
        }
        double db = 20 * Math.Log10(peak);
        if (db > -1 || db <= -30) return string.Format("pico {0:0.0} dBFS", db);
        return "";
    }
}
'@

$raiz = $PSScriptRoot
$fallos = 0
$a = Join-Path ([System.IO.Path]::GetTempPath()) ('rodaje-sonidos-a-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$b = Join-Path ([System.IO.Path]::GetTempPath()) ('rodaje-sonidos-b-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
try {
    foreach ($d in @($a, $b)) {
        & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $raiz 'generar.ps1') -Destino $d | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "generar.ps1 falló" }
    }

    $manifiesto = [System.IO.File]::ReadAllText((Join-Path $raiz 'paquete.json')) | ConvertFrom-Json
    $esperados = @{}
    foreach ($e in $manifiesto.items) {
        if ($e.kind -ne 'sound') { Write-Host "  $($e.id): kind $($e.kind)" -ForegroundColor Red; $fallos++; continue }
        if ($e.description -notmatch '·\s*([\d,]+)\s*s$') { Write-Host "  $($e.id): la descripción no dice la duración" -ForegroundColor Red; $fallos++; continue }
        $ms = [double]::Parse($Matches[1].Replace(',', '.'), [Globalization.CultureInfo]::InvariantCulture) * 1000
        $ruta = Join-Path $a ($e.file.Replace('/', '\'))
        $esperados[$ruta.ToLowerInvariant()] = $true
        if (-not (Test-Path -LiteralPath $ruta)) { Write-Host "  $($e.id): falta $($e.file)" -ForegroundColor Red; $fallos++; continue }
        $motivo = [WavCheck]::Check($ruta, $ms, $e.description.StartsWith('Ambiente en bucle'))
        if ($motivo) { Write-Host "  $($e.id): $motivo" -ForegroundColor Red; $fallos++ }
        $h1 = (Get-FileHash -LiteralPath $ruta -Algorithm SHA256).Hash
        $h2 = (Get-FileHash -LiteralPath (Join-Path $b ($e.file.Replace('/', '\'))) -Algorithm SHA256).Hash
        if ($h1 -ne $h2) { Write-Host "  $($e.id): dos corridas dan bytes distintos" -ForegroundColor Red; $fallos++ }
    }
    foreach ($f in Get-ChildItem -LiteralPath $a -Recurse -File) {
        if (-not $esperados.ContainsKey($f.FullName.ToLowerInvariant())) { Write-Host "  Sobra $($f.FullName)" -ForegroundColor Red; $fallos++ }
    }
    $ids = @($manifiesto.items | ForEach-Object { $_.id })
    if (($ids | Sort-Object -Unique).Count -ne $ids.Count) { Write-Host '  Hay ids repetidos' -ForegroundColor Red; $fallos++ }

    if ($fallos -eq 0) { Write-Host "  $($ids.Count) sonidos: todo bien (mismos bytes en dos corridas)." -ForegroundColor Green; exit 0 }
    Write-Host "  $fallos fallos." -ForegroundColor Red
    exit 1
} finally {
    foreach ($d in @($a, $b)) { if (Test-Path -LiteralPath $d) { Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue } }
}
