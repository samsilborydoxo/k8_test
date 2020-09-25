#!/bin/bash 

namespace="nirmata"
pod="."
taillines="--tail 50000"
datastamp=$(date "+%Y%m%d-%H%M%S")
startdir=$(pwd)
zip="gzip"
zip_ext="gz"

helpfunction(){
    echo "script usage: $(basename "$0") [-n namespace] [-t number_of_log_lines] [ -p pod_name_regex ] [-a] [-x] [-l compression_level] " >&2
    echo "  -a  All lines" >&2
    echo "  -x  Use xz compression" >&2
    echo "  -l  Use this compression level" >&2
}

while getopts 't:p:n:l:hax' OPTION; do
  case "$OPTION" in
    p)
      pod="$OPTARG"
      ;;
    n)
      namespace="$OPTARG"
      ;;
    t)
      taillines="--tail $OPTARG"
      ;;
    a)
      taillines=""
      ;;
    x)
      if command -v xz &> /dev/null;then 
          zip="xz"
          zip_ext=$zip
      else
          echo "xz not found in PATH using gzip"
      fi
      ;;
    l)
      level="-$OPTARG"
      ;;
    h)
      helpfunction
      exit 0
      ;;
    ?)
      helpfunction
      exit 1
      ;;
  esac
done
shift "$(($OPTIND -1))"

# Bzip -0 is better and faster than gzip default, and for text the standard level isn't much better and much slower.
if [[ $zip == "bz" ]];then 
    if [ -z "$level" ];then 
        level="-0"
    fi
fi

echo "namespace is $namespace"
echo "pod match string is $pod"

running_pods=$(kubectl get pods --no-headers -o custom-columns=":metadata.name" -n "$namespace"  |grep "$pod")
if [ -z "$running_pods" ]; then 
    echo "No pods found for $pod in  $namespace"
    exit 0
fi
echo -e "Found runing pods: \n$running_pods"
echo 

rm -rf "/tmp/k8-logs-script-$namespace-$datastamp"
if [ -e /tmp/k8-logs-script-"$namespace-$datastamp" ];then echo "/tmp/k8-logs-script-$namespace-$datastamp exists bailing out"; exit 1; fi
mkdir "/tmp/k8-logs-script-$namespace-$datastamp"
cd /tmp/k8-logs-script-"$namespace"-"$datastamp" || exit


for curr_pod in $running_pods; do
   kubectl -n "$namespace" logs "$curr_pod" --all-containers=true $taillines | $zip $level > "${curr_pod}.log.$zip_ext"
   kubectl -n "$namespace" describe pods "$curr_pod"  2>&1 >>"${curr_pod}".describe
   # Less awk more formating?
   (kubectl -n "$namespace" describe $(kubectl -n "$namespace" describe $(kubectl -n "$namespace" describe pod "$curr_pod" 2>/dev/null|grep Controlled.By: |awk '{print $3}')  |grep Controlled.By: |awk '{print $3}') --show-events 2>&1) >>"${curr_pod}".describe
done


for described in $(ls *.describe);do 
    $zip $level $described
done


cd "$startdir" || exit
tar czf "k8-logs-script-$namespace-$datastamp.tar" -C /tmp "k8-logs-script-$namespace-$datastamp"
echo "Created k8-logs-script-$namespace-$datastamp.tar" 

rm -rf "/tmp/k8-logs-script-$namespace-$datastamp"