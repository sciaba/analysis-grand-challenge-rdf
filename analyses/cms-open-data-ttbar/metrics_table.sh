#! /bin/bash

test=$1
w=(1 2 4 8 16 32 64 128)
echo "workers,wtime,wtime_err,cputime,cputime_err,cpu_eff,cpu_eff_err,rate,rate_err,read,read_err"
for i in ${w[@]} ; do
    ./metrics_csv.sh ${test}_$i
done
