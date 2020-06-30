#!/bin/bash -x

namespace="nirmata"
pod="."
taillines=50000
datastamp=$(date "+%Y%m%d-%H%M%S")
startdir=$(pwd)

while getopts 't:p:n:h' OPTION; do
  case "$OPTION" in
    p)
      pod="$OPTARG"
      ;;
    n)
      namespace="$OPTARG"
      ;;
    t)
      taillines="$OPTARG"
      ;;
    h)
      echo "script usage: $(basename "$0") [-n namespace] [-t number_of_log_lines] [ -p pod_name ]" >&2
      exit 0
      ;;
    ?)
        echo "script usage: $(basename "$0") [-n namespace] [-t number_of_log_lines] [ -p match_string_4_pods ]" >&2
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
echo "Found runing pods: $running_pods"
echo 

rm -rf "/tmp/k8-logs-script-$namespace-$datastamp"
if [ -e /tmp/k8-logs-script-"$namespace-$datastamp" ];then echo "/tmp/k8-logs-script-$namespace-$datastamp exists bailing out"; exit 1; fi
mkdir "/tmp/k8-logs-script-$namespace-$datastamp"
cd /tmp/k8-logs-script-"$namespace"-"$datastamp" || exit


for curr_pod in $running_pods; do
   kubectl -n "$namespace" logs "$curr_pod" --all-containers=true --tail "$taillines" &>"${curr_pod}.log"
   kubectl -n "$namespace" describe pods "$curr_pod"  >>"${curr_pod}".describe
   # Less awk more formating?
   kubectl -n "$namespace" describe $(kubectl -n "$namespace" describe $(kubectl -n "$namespace" describe pod "$curr_pod" |grep Controlled.By: |awk '{print $3}')  |grep Controlled.By: |awk '{print $3}') --show-events >>"${curr_pod}".describe
done

cd "$startdir" || exit
tar czf "k8-logs-script-$namespace-$datastamp.tgz" -C /tmp "k8-logs-script-$namespace-$datastamp"
echo "k8-logs-script-$namespace-$datastamp.tgz" 
rm -rf "/tmp/k8-logs-script-$namespace-$datastamp"
