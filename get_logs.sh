#!/bin/bash

namespace="nirmata"
pod="."
taillines=50000
datastamp=$(date "+%Y%m%d-%H%M%S")
startdir=$(pwd)

while getopts 't:p:n:' OPTION; do
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
    ?)
      echo "script usage: $(basename $0) [-n namespace] [-t number_of_log_lines] [ -p pod_name ]" >&2
      exit 1
      ;;
  esac
done
shift "$(($OPTIND -1))"

echo "namespace is $namespace"
echo "pods is $pod"

running_pods=$(kubectl get pods --no-headers -o custom-columns=":metadata.name" -n $namespace  |grep $pod)
echo runing pods $running_pods

rm -rf /tmp/k8-logs-script-$namespace-$datastamp
if [ -e /tmp/k8-logs-script-$namespace-$datastamp ];then echo /tmp/k8-logs-script-$namespace-$datastamp exists bailing out; exit 1; fi
mkdir /tmp/k8-logs-script-$namespace-$datastamp
cd /tmp/k8-logs-script-"$namespace"-"$datastamp" || exit


for curr_pod in $running_pods; do
   kubectl -n $namespace logs $curr_pod --tail $taillines &>${curr_pod}.log
done

cd "$startdir" || exit
tar czf k8-logs-script-$namespace-$datastamp.tgz -C /tmp k8-logs-script-$namespace-$datastamp
