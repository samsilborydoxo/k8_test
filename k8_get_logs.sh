#!/bin/bash -x

namespace="nirmata"
pod="."
taillines="--tail 50000"
datastamp=$(date "+%Y%m%d-%H%M%S")
startdir=$(pwd)
zip="gzip"

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
      zip="xz"
      ;;
    l)
      level="$OPTARG"
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
   kubectl -n "$namespace" logs "$curr_pod" --all-containers=true $taillines | $zip > "${curr_pod}.log.$zip"
   kubectl -n "$namespace" describe pods "$curr_pod"  2>&1 >>"${curr_pod}".describe
   # Less awk more formating?
   (kubectl -n "$namespace" describe $(kubectl -n "$namespace" describe $(kubectl -n "$namespace" describe pod "$curr_pod" 2>/dev/null|grep Controlled.By: |awk '{print $3}')  |grep Controlled.By: |awk '{print $3}') --show-events 2>&1) >>"${curr_pod}".describe
done

cd "$startdir" || exit
tar czf "k8-logs-script-$namespace-$datastamp.tgz" -C /tmp "k8-logs-script-$namespace-$datastamp"
echo "k8-logs-script-$namespace-$datastamp.tgz" 

rm -rf "/tmp/k8-logs-script-$namespace-$datastamp"
