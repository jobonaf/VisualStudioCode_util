param(
    [string]$file = "main.tex",
    [switch]$pdf,
    [switch]$xelatex,
    [switch]$lualatex,
    [switch]$bibtex,
    [switch]$biber,
    [switch]$pvc,
    [Alias("c")]
    [switch]$clean,
    [switch]$fullclean,
    [switch]$quiet,
    [switch]$verbose,
    [string]$auxdir = "",   # directory ausiliari
    [string]$outdir = ""    # directory output
)

# Funzioni di logging
function Log-Info($msg) { if (-not $quiet) { Write-Host "[INFO] $msg" } }
function Log-Verbose($msg) { if ($verbose) { Write-Host "[VERBOSE] $msg" } }

# Configurazione motori
if ($xelatex) {
    $engine = "xelatex"
}
elseif ($lualatex) {
    $engine = "lualatex"
}
else {
    $engine = "pdflatex"
}

if ($biber) {
    $bibTool = "biber"
}
else {
    $bibTool = "bibtex"
}

# File temporanei per pulizia
$lightCleanFiles = @("*.aux", "*.log", "*.bbl", "*.blg", "*.out", "*.toc", "*.lof", "*.lot", "*.fls", "*.fdb_latexmk")
$fullCleanFiles = $lightCleanFiles + @("*.synctex.gz", "*.pdf", "*.dvi", "*.nav", "*.snm", "*.vrb")

# Funzione di pulizia
if ($clean -or $fullclean) {
    $filesToRemove = if ($fullclean) { $fullCleanFiles } else { $lightCleanFiles }
    Log-Info "Pulizia $(if ($fullclean) {"completa"} else {"leggera"}) in corso..."
    foreach ($pattern in $filesToRemove) {
        Log-Verbose "Rimuovendo file: $pattern"
        Get-ChildItem -Path $pattern -Recurse -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
    }
    Log-Info "Pulizia completata."
    exit
}

# Prepara argomenti aggiuntivi per il motore
$engineArgs = @("-interaction=nonstopmode", "-synctex=1")
if ($auxdir -ne "") {
    Log-Verbose "Impostata auxdir: $auxdir"
    if (-not (Test-Path $auxdir)) {
        Log-Info "Creazione directory ausiliari $auxdir..."
        New-Item -ItemType Directory -Force -Path $auxdir | Out-Null
    }
    $engineArgs += "-aux-directory=$auxdir"
}
if ($outdir -ne "") {
    Log-Verbose "Impostata outdir: $outdir"
    if (-not (Test-Path $outdir)) {
        Log-Info "Creazione directory output $outdir..."
        New-Item -ItemType Directory -Force -Path $outdir | Out-Null
    }
    $engineArgs += "-output-directory=$outdir"
}

# Funzione di compilazione
function Invoke-LaTeX([string]$inputFile) {
    Log-Info "Compilazione con $engine..."
    Log-Verbose "Comando: $engine $engineArgs $inputFile"
    
    & $engine @engineArgs $inputFile
    if ($LASTEXITCODE -ne 0) {
        Log-Info "Errore nella compilazione del file $inputFile"
        return
    }

    # BibTeX / Biber - MODIFICATO PER GESTIRE AUXDIR
    $auxFileBaseName = [System.IO.Path]::GetFileNameWithoutExtension($inputFile)
    $auxFile = [System.IO.Path]::Combine($auxdir, $auxFileBaseName + ".aux")
    
    if (Test-Path $auxFile) {
        Log-Info "Esecuzione $bibTool..."
        
        if ($biber) {
            # Per Biber: passa il percorso completo del file .aux
            & $bibTool $auxFile
        }
        else {
            if ($auxdir -ne "") {
                # Imposta BIBINPUTS per dire a BibTeX dove cercare i file .bib
                $env:BIBINPUTS = "$((Get-Location).Path);$auxdir;"
                Log-Verbose "BIBINPUTS impostato: $env:BIBINPUTS"
            }
            # Per BibTeX: cambia directory temporaneamente nella auxdir
            $originalLocation = Get-Location
            try {
                Set-Location -Path $auxdir
                & $bibTool $auxFileBaseName
            }
            finally {
                Set-Location -Path $originalLocation
            }
            # Ripristina BIBINPUTS dopo
            if ($auxdir -ne "") {
                $env:BIBINPUTS = $null
            }
        }
        
        if ($LASTEXITCODE -ne 0) {
            Log-Info "Errore nell'esecuzione di $bibTool"
            return
        }
    }
    else {
        Log-Info "File .aux non trovato: $auxFile"
    }

    # Ricompilazioni per riferimenti incrociati
    Log-Info "Seconda compilazione per riferimenti incrociati..."
    & $engine @engineArgs $inputFile
    
    Log-Info "Terza compilazione per riferimenti bibliografici..."
    & $engine @engineArgs $inputFile
    
    Log-Info "Compilazione completata."
}

# Modalità PVC (watch)
if ($pvc) {
    Log-Info "Monitoraggio modifiche (CTRL+C per interrompere)..."
    $watcher = New-Object System.IO.FileSystemWatcher
    $watcher.Path = (Get-Location).Path
    $watcher.Filter = "*.tex"
    $watcher.IncludeSubdirectories = $true
    $watcher.EnableRaisingEvents = $true

    $action = {
        $changedFile = $Event.SourceEventArgs.Name
        Log-Verbose "File modificato: $changedFile"
        Invoke-LaTeX -inputFile $file
    }

    Register-ObjectEvent $watcher "Changed" -Action $action | Out-Null
    try { 
        while ($true) { Start-Sleep -Seconds 1 } 
    }
    finally { 
        Unregister-Event -SourceIdentifier $watcher -ErrorAction SilentlyContinue 
    }
}
else {
    Invoke-LaTeX -inputFile $file
}