#!/usr/bin/env python3
"""
Static elaboration of the design and every test bench with slang
(pip install pyslang).  Catches syntax errors, undeclared identifiers, port
mismatches and width problems without a simulator.
Usage:  python3 scripts/lint_slang.py [-v] [top ...]
   -v  also print warnings (sign conversion, width, mixed arithmetic)
"""
import os, sys, glob
import pyslang

base = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
rtl  = sorted(glob.glob(os.path.join(base, "CORDIC.srcs", "sources_1", "new", "*.v")))
sim  = sorted(glob.glob(os.path.join(base, "CORDIC.srcs", "sim_1", "new", "*.v")))
args = [a for a in sys.argv[1:] if not a.startswith("-")]
verbose = "-v" in sys.argv
tops = args or ["cordic_fm_top", "tb_cordic_engine", "tb_awgn_gen", "tb_audio_lpf", "tb_sd_dac",
                "tb_bin2bcd", "tb_mic_adc_spi", "tb_da2_dac_spi", "tb_kypd_scanner",
                "tb_recip_divider", "tb_fm_dsp_core", "tb_cordic_fm_system", "tb_cordic_fm_top"]
IGNORE = {"WidthTruncate", "WidthExpand", "EmptyOutputPortConn", "CaseDefault"}
rc = 0
for top in tops:
    files = rtl if top == "cordic_fm_top" else rtl + sim
    d = pyslang.driver.Driver()
    d.addStandardArgs()
    d.parseCommandLine(" ".join(["slang", "--top", top, "-Wextra", "--allow-use-before-declare"] + files))
    d.processOptions()
    d.parseAllSources()
    comp = d.createCompilation()
    diags = comp.getAllDiagnostics()
    engine = pyslang.DiagnosticEngine(d.sourceManager)
    client = pyslang.TextDiagnosticClient()
    engine.addClient(client)
    nerr = 0; nwarn = 0
    for dg in diags:
        name = str(dg.code).replace("DiagCode(", "").rstrip(")")
        sev = engine.getSeverity(dg.code, dg.location)
        if sev in (pyslang.DiagnosticSeverity.Error, pyslang.DiagnosticSeverity.Fatal):
            nerr += 1; engine.issue(dg)
        elif name not in IGNORE:
            nwarn += 1
            if verbose: engine.issue(dg)
    txt = client.getString()
    if txt.strip(): print(txt)
    print(f"== {top}: {'OK' if nerr == 0 else 'ERRORS'}  ({nerr} errors, {nwarn} warnings worth a look)")
    if nerr: rc = 1
sys.exit(rc)
