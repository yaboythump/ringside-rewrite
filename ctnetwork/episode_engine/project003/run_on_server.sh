#!/bin/bash
# Project 003 server runbook. Dev sandbox only: reads production jobs, writes only under
# /srv/ctnetwork-dev/project003 (plus one private review folder when STAGE=1).
# Zero generation credits. Nothing is published. No service is touched. Low priority (nice 15 / ionice idle).
#   bash run_on_server.sh <ENGINE_DIR>
set -uo pipefail
ENG=${1:?engine dir}
DEV=/srv/ctnetwork-dev
P=$DEV/project003
PY=/srv/ctnetwork/venv/bin/python
JOB=/srv/ctnetwork/jobs/ringside-rewrite-raven-flock-20261104
PUBLISHED=$JOB/outputs/Ringside_Rewrite_What_If_Ravens_Flock_Took_Over_WCW.mp4
P002=$DEV/renders/ringside-rewrite-raven-flock-20261104/Ringside_Rewrite_What_If_Ravens_Flock_Took_Over_WCW.mp4
HHR=/srv/ctnetwork/jobs/hip-hop-rewind-e001-stack-bundles-network-logo-r8
POC=$P/renders/raven-poc
LOW="nice -n 15 ionice -c3"
mkdir -p $P/renders $P/qc
LOG=$P/run.log
step(){ echo "== $(date -Is) $*" | tee -a $LOG; }
step START engine=$ENG

if [ "${ONLY_POC:-0}" != "1" ]; then step TESTS
PYTHONPATH=$DEV/pylib $LOW $PY -m pytest -q $ENG/tests > $P/test_results.txt 2>&1; echo "tests_rc=$?" >> $LOG
tail -3 $P/test_results.txt >> $LOG; fi

step POC_RENDER
$LOW $PY $ENG/run_job.py $JOB --out $POC --planner coverage --excerpt 60-90 \
  --output-name Ringside_Rewrite_Raven_POC_Cinematic.mp4 --compare $PUBLISHED $P002 --threads 3 >> $LOG 2>&1
echo "poc_rc=$?" >> $LOG

step SIDE_BY_SIDE
OUTV=$(ls $POC/Ringside_Rewrite_Raven_POC_Cinematic.mp4 2>/dev/null)
if [ -n "$OUTV" ]; then
  T=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$OUTV")
  F=/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf
  $LOW ffmpeg -y -v error -t "$T" -i "$PUBLISHED" -i "$OUTV" -filter_complex \
   "[0:v]scale=954:-2,setsar=1[a];[1:v]scale=954:-2,setsar=1[b];color=c=0x0b0b0e:s=1920x1080:r=30:d=$T[bg];[bg][a]overlay=4:268:shortest=1[t];[t][b]overlay=962:268:shortest=1,drawtext=fontfile=$F:text='BEFORE  published 2026-11-04':fontsize=34:fontcolor=white:x=40:y=200,drawtext=fontfile=$F:text='AFTER  Project 003 engine':fontsize=34:fontcolor=0xffd36b:x=998:y=200,drawtext=fontfile=$F:text='same narration  same stills  same music  same formula':fontsize=26:fontcolor=white@0.8:x=(w-tw)/2:y=850,format=yuv420p[v]" \
   -map "[v]" -map 1:a -c:v libx264 -preset medium -crf 20 -c:a aac -b:a 160k -t "$T" -movflags +faststart $POC/Raven_POC_Before_After.mp4 >> $LOG 2>&1
  echo "sbs_rc=$?" >> $LOG
fi

if [ "${ONLY_POC:-0}" != "1" ]; then
step FULL_EPISODE_PLANS
$LOW $PY $ENG/run_job.py $JOB --out $P/renders/raven-plan-coverage --planner coverage --episode-only --plan-only >> $LOG 2>&1
$LOW $PY $ENG/run_job.py $JOB --out $P/renders/raven-plan-approved --planner approved --episode-only --plan-only >> $LOG 2>&1

step FULL_VISUAL_QC
$LOW $PY $ENG/visual_qc.py "$PUBLISHED" --formula $ENG/formulas/ringside_rewrite.json --contact-dir $P/qc --out $P/qc/published_raven_full.json >> $LOG 2>&1
[ -f "$P002" ] && $LOW $PY $ENG/visual_qc.py "$P002" --formula $ENG/formulas/ringside_rewrite.json --contact-dir $P/qc/p002 --out $P/qc/project002_raven_full.json >> $LOG 2>&1
$LOW $PY $ENG/visual_qc.py $JOB/outputs/Raven_Short_1.mp4 $JOB/outputs/Raven_Short_2.mp4 $JOB/outputs/Raven_Short_3.mp4 --formula $ENG/formulas/ringside_rewrite.json --shorts --out $P/qc/published_raven_shorts.json >> $LOG 2>&1
$LOW $PY $ENG/visual_qc.py $HHR/outputs/Hip_Hop_Rewind_E001_Stack_Bundles.mp4 --formula $ENG/formulas/hip_hop_rewind.json --contact-dir $P/qc --ledger $HHR/outputs/Editing_Source/episode_edit.json --out $P/qc/hip_hop_rewind_e001.json >> $LOG 2>&1

fi
step HHWI_ASSET_SCAN
{ ls /srv/ctnetwork/assets; find /srv/ctnetwork/assets /srv/ctnetwork/jobs/hhwi-* -maxdepth 3 \( -iname '*hiphop*what*' -o -iname '*hhwi*' -o -iname 'music_bed*' -o -iname '*Intro_Recent*' \) 2>/dev/null | head -40; } > $P/hhwi_asset_scan.txt

step SUMMARY
$PY $ENG/project003/summarize.py $P > $P/summary.txt 2>&1
if [ "${STAGE:-0}" = "1" ]; then step STAGE; $PY $ENG/project003/stage_review.py $P >> $LOG 2>&1; fi
step DONE
touch $P/DONE
