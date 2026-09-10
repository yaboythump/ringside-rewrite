from pathlib import Path

base = Path(__file__).resolve().parent / 'build_v3.py'
src = base.read_text(encoding='utf-8')
src = src.replace("d=.25", "d=0.25").replace("d=.30", "d=0.30")
ns = {'__name__': '__main__', '__file__': str(base)}
exec(compile(src, str(base), 'exec'), ns, ns)
