#! /bin/bash

# Default values
maxjobs=9
afname="cms-xrootd"
workers=4

usage() {
    echo "Usage : run_rdf_ttbar.sh [-n NFILES] -a AFNAME -w NWORKERS [-r] [-x hdd|sdd] [-p] [-h]"
    echo
    echo "        -n NFILES: specify the maximum number of files per dataset"
    echo "        -a AFNAME: specify the data source. Possible choices:"
    echo "                   cms-xrootd: from EOSCMS via xrootd"
    echo "                   cms-http: from EOSCMS via HTTPS"
    echo "                   pilot-xrootd: from EOSPILOT via xrootd"
    echo "                   pilot-http: from EOSPILOT via HTTP"
    echo "                   cern-local: from the local filesystem of iopef01"
    echo "        -w NWORKERS: specify how many workers should be used"
    echo "        -x hdd/ssd: read through the CERN X-Cache instance"
    echo "        -p: add export XRD_PARALLELEVTLOOP=10 to optimise xrootd I/O"
    echo "        -r: use the RNTuple dataset (default is TTree)"
    echo "        -h: this help message"
}

while getopts "n:a:w:x:prh" arg; do
    case $arg in
	n)
	    nfiles=$OPTARG
	    ;;
	a)
	    afname=$OPTARG
	    ;;
	w)
	    workers=$OPTARG
	    ;;
	s)
	    substreams=$OPTARG
	    ;;
	x)
	    xcache=$OPTARG
	    ;;
	p)
	    xrdopt=1
	    ;;
	r)
	    rntuple=1
	    ;;
        ?|h)
	    usage
	    exit 1
	    ;;
    esac
done

ulimit -n 4096

ARGS=''
if [ -z "${nfiles}" ] ; then
    nfiles='all'
else
    ARGS="-n ${nfiles} "
fi

ARGS="$ARGS -c ${workers}"

if [ -z "${rntuple}" ] ; then
    WDIR="rdf_ttbar_ttree_run_"
    dataset="agc_nanoaod.txt"
else
    WDIR="rdf_ttbar_rntuple_run_"
    dataset="agc_rntuple.txt"
fi

if [ -n "${xrdopt}" ] ; then
    export XRD_PARALLELEVTLOOP=10
    WDIR="${WDIR}xrd_"
fi

if [ -n "${substreams}" ] ; then
   export XRD_SUBSTREAMSPERCHANNEL=${substreams}
   WDIR="${WDIR}ss-${substreams}_"
fi

if [ -z "${xcache}" ] ; then
    xcache='False'
elif [ "${xcache}" == 'hdd' ] ; then
    WDIR="${WDIR}xcache_"
    ssh root@xcache01.cern.ch sysctl vm.drop_caches=3
    if [[ $? != 0 ]] ; then
        echo "Could not clear cache. Exiting..."
	exit 1
    fi
elif [ "${xcache}" == 'hdd2' ] ; then
    WDIR="${WDIR}xcache2_"
    ssh root@xcache02.cern.ch sysctl vm.drop_caches=3
    if [[ $? != 0 ]] ; then
        echo "Could not clear cache. Exiting..."
	exit 1
    fi
elif [ "${xcache}" == 'ssd' ] ; then
    WDIR="${WDIR}xcachessd_"
    ssh root@xcache03.cern.ch sysctl vm.drop_caches=3
fi

WDIR="${WDIR}${nfiles}_${afname}_${workers}"
njobs=$(ls -1d ${WDIR} ${WDIR}.* 2> /dev/null | wc -l)
if [[ $njobs -ge ${maxjobs} ]] ; then
    echo "Enough jobs already. Exiting..."
    exit 2
fi
pre=$(ls -1d ${WDIR}.* 2> /dev/null | tail -1)
if [ -n "$pre" ] ; then
    pre=${pre: -1}
else
    pre=0
fi
new=$((pre + 1))
if [ -d $WDIR ] ; then
    echo "Moving $WDIR to $WDIR.$new"
    mv $WDIR $WDIR.$new
fi
mkdir ${WDIR}
if [ $? != 0 ] ; then
    echo "Could not create test dir. Exiting..."
    exit 1
fi

cd ${WDIR}
if [[ "${afname}" == 'cms-xrootd' ]] ; then
    cat ../nanoaod_inputs.json | sed 's#https://xrootd-local.unl.edu:1094//store/user/AGC#root://eoscms.cern.ch//eos/cms/opstest/asciaba/agc/datasets#' > nanoaod_inputs.json
elif [[ "${afname}" == 'pilot-xrootd' ]] ; then
    cat ../nanoaod_inputs.json | sed 's#https://xrootd-local.unl.edu:1094//store/user/AGC#root://eospilot.cern.ch//eos/pilot/rntuple/agc/datasets#' > nanoaod_inputs.json
elif [[ "${afname}" == 'local-xrootd' ]] ; then
    cat ../nanoaod_inputs.json | sed 's#https://xrootd-local.unl.edu:1094//store/user/AGC#/data/datasets/agc/datasets#' > nanoaod_inputs.json
fi

if [[ "${rntuple}" -eq 1 ]] ; then
    sed -i 's/nanoAOD/nanoAODRNTuple/' nanoaod_inputs.json
fi

ln -s ../analysis.py .
ln -s ../helpers.h .
ln -s ../helpers_h_ACLiC_dict_rdict.pcm .
ln -s ../helpers_h.d .
ln -s ../helpers_h.so .
ln -s ../ml_helpers.cpp .
ln -s ../ml.py .
ln -s ../models .
ln -s ../plotting.py .
ln -s ../utils.py .

export EXTRA_CLING_ARGS="-O2"
export XRD_APPNAME="AGCRDF"
export XRD_RECORDERPATH=$PWD/xrdrecord.csv

env > env.out
sudo sysctl vm.drop_caches=3

prmon -i 5 -- python ./analysis.py $ARGS -o output.root > stdout 2> stderr
echo "RETURN CODE: $?" >> stdout
