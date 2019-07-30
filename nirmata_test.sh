#!/bin/bash
# shellcheck disable=SC1117,SC2086,SC2001

# This might be better done in python or ruby, but we can't really depend on those existing or having useful modules.

#default external dns target
DNSTARGET=nirmata.com
SERVICETARGET=kubernetes.default.svc.cluster.local
# set to zero to default to all namespaces
allns=1
# set to zero to default to curl url
curl=1
# Default namespace
namespace="nirmata"
# Should we continue to execute on failure
CONTINUE="yes"
# Set to yes to be quieter
QUIET="no"
# set to 1 to disable local tests to 0
run_local=1
# set to 1 to disable remote tests to 0
run_remote=1
# These are used to run the mongo, zookeeper, and kafka tests by default.
run_mongo=1
run_zoo=1
run_kafka=1
# Did we get an error?
export error=0
# Did we get a warning?
export warn=0
nossh=0
script_args=""
# shellcheck disable=SC2124
all_args="$@"
# We should do something if there is no instruction for us
if [[ ! $all_args == *--cluster* ]] ; then
    if [[ ! $all_args == *--local* ]] ; then
        if [[ ! $all_args == *--nirmata* ]] ; then
            run_mongo=0
            run_zoo=0
            run_kafka=0
        fi
    fi
fi
email=1
sendemail='ssilbory/sendemail'
alwaysemail=1
# Set this to fix local issues by default
fix_issues=1
# warnings return 2
warnok=1
#additional args for kubectl
add_kubectl=""

if [ -f /.dockerenv ]; then
    export INDOCKER=0
else
    export INDOCKER=1
fi

#function to print red text
error(){
    error=1
    # shellcheck disable=SC2145
    echo -e "\e[31m${@}\e[0m"
    if [ "$CONTINUE" = "no" ];then
        echo -e "\e[31mContinue is not set exiting on error!\e[0m"
       namespaces="$(kubectl get ns  --no-headers | awk '{print $1}')"
       for ns in $namespaces;do
          kubectl --namespace=$ns delete ds nirmata-net-test-all --ignore-not-found=true &>/dev/null
        done
        kubectl --namespace=$namespace delete ds nirmata-net-test-all --ignore-not-found=true &>/dev/null
        # THIS EXITS THE SCRIPT
        exit 1
    fi
}
#function to print yellow text
warn(){
    warn=1
    # shellcheck disable=SC2145
    echo -e "\e[33m${@}\e[0m"
}
#function to print green text
good(){
    if [ ! "$QUIET" = "yes" ];then
        # shellcheck disable=SC2145
        echo -e "\e[32m${@}\e[0m"
    fi
}
helpfunction(){
    echo "Note that this script requires access to the following containers:"
    echo "nicolaka/netshoot for cluster tests."
    echo "ssilbory/sendemail for sending email."
    echo "Usage: $0"
    echo "--allns                     Test all namespaces (Default is only \"$namespace\")"
    echo '--dns-target dns.name       (Default nirmata.com)'
    #echo '--exit                     Exit on errors'
    echo '--https                     Curl the service with https.'
    echo '--http                      Curl the service with http.'
    echo '--local                     Run local tests'
    echo '--nirmata                   Run Nirmata app tests'
    echo '-q                          Do not report success'
    echo "--warnok                    Do not exit 2 on warnings."
    echo "--namespace namespace_name  (Default is \"$namespace\")."
    echo '--cluster                   Run Nirmata K8 cluster tests'
    echo "--service service_target    (Default $SERVICETARGET)."
    echo "--fix                       Attempt to fix issues (local only)"
    echo "--ssh \"user@host.name\"    Ssh to a space-separated list of systems and run local tests"
    echo "Note that --ssh does not return non-zero on failure on ssh targets.  Parse for:"
    echo "  'Test completed with errors'"
    echo "  'Test completed with warnings'"
    echo
    echo "Email Settings (Note that these options are incompatible with --ssh.)"
    echo "--email                     Enables email reporting on error"
    echo "--to some.one@some.domain   Sets the to address.  Required"
    echo "--from email@some.domain    Sets the from address. (default k8@nirmata.com)"
    echo "--subject 'something'       Sets the email subject. (default 'K8 test script error')"
    echo "--smtp smtp.server          Set your smtp server.  Required"
    echo "--user user.name            Sets your user name. Optional"
    echo "--passwd 'L33TPASSW)RD'     Set your password.  Optional"
    echo "--email-opts '-o tls=yes'   Additional options to send to the sendemail program."
    echo "--always-email              Send emails on warning and good test results"
    echo "--sendemail                 Set the container used to send email."
    echo "Simple open smtp server:"
    echo "$0 --email --to testy@nirmata.com --smtp smtp.example.com"
    echo "Authenication with an smtp server:"
    echo "--email --to testy@nirmata.com --smtp smtp.example.com  --user sam.silbory --passwd 'foo!foo'"
    echo "Authenication with gmail: (Requires an app password be used!)"
    echo "--email --to testy@nirmata.com --smtp smtp.gmail.com:587  --user sam.silbory --passwd 'foo!foo'"
}

# deal with args
# This for loop is getting out of control it might be worth using getops or something.
for i in "$@";do
    case $i in
        --dns-target)
            script_args=" $script_args $1 $2 "
            DNSTARGET=$2
            shift
            shift
            echo DNSTARGET is $DNSTARGET
        ;;
        --service)
            script_args=" $script_args $1 $2 "
            SERVICETARGET=$2
            shift
            shift
            echo SERVICETARGET is $SERVICETARGET
        ;;
        --continue|-c)
            script_args=" $script_args $1 "
            CONTINUE="yes"
            shift
        ;;
        --allns)
            script_args=" $script_args $1 "
            allns=0
            shift
        ;;
        --https)
            script_args=" $script_args $1 "
            curl=0
            http=1
            shift
        ;;
        --http)
            script_args=" $script_args $1 "
            curl=0
            http=0
            shift
        ;;
        --namespace)
            script_args=" $script_args $1 $2 "
            namespace=$2
            shift
            shift
        ;;
        --local)
            script_args=" $script_args $1 "
            run_local=0
            if [[ ! $all_args == *--cluster* ]] ; then
                run_remote=1
            fi
            shift
        ;;
        --cluster)
            script_args=" $script_args $1 "
            if [[ ! $all_args == *--local* ]] ; then
                run_local=1
            fi
            run_remote=0
            shift
        ;;
        --nirmata)
            script_args=" $script_args $1 "
            run_mongo=0
            run_zoo=0
            run_kafka=0
            if [[ ! $all_args == *--cluster* ]] ; then
                run_remote=1
            fi
            if [[ ! $all_args == *--local* ]] ; then
                run_local=1
            fi
            shift
        ;;
        --exit)
            script_args=" $script_args $1 "
            CONTINUE="no"
            shift
        ;;
        --insecure)
            script_args=" $script_args $1 $2 "
            add_kubectl=" $add_kubectl --insecure-skip-tls-verify=false "
            shift
        ;;
        --client-cert)
            add_kubectl=" $add_kubectl --client-certificate=$2"
            shift
            shift
        ;;
        -q)
            script_args=" $script_args $1 "
            QUIET="yes"
            shift
        ;;
        --ssh)
            ssh_hosts=$2
            nossh=1
            shift
            shift
        ;;
        --nossh)
            script_args=" $script_args $1 "
            nossh=0
            shift
        ;;
        --fix)
            fix_issues=0
            shift
        ;;
        --logfile)
            script_args=" $script_args $1 $2 "
            logfile=$2
            shift
            shift
        ;;
        --email)
            script_args=" $script_args $1 "
            email=0
            shift
        ;;
        --to)
            script_args=" $script_args $1 $2 "
            TO=$2
            shift
            shift
        ;;
        --from)
            script_args=" $script_args $1 $2 "
            FROM=$2
            shift
            shift
        ;;
        --subject)
            script_args=" $script_args $1 $2 "
            SUBJECT=$2
            shift
            shift
        ;;
        --smtp)
            script_args=" $script_args $1 $2 "
            SMTP_SERVER=$2
            shift
            shift
        ;;
        --user)
            script_args=" $script_args $1 $2 "
            EMAIL_USER=$2
            shift
            shift
        ;;
        --passwd)
            script_args=" $script_args $1 $2 "
            EMAIL_PASSWD=$2
            shift
            shift
        ;;
        --sendemail)
            sendemail=$2
            shift
            shift
        ;;
        --always-email)
            alwaysemail=0
            shift
        ;;
        --warnok)
            script_args=" $script_args $1 "
            warnok=0
            shift
        ;;
        #--email-opts)
        #    script_args=" $script_args $1 $2 "
        #    EMAIL_OPTS="\'$2\'"
        #    shift
        #    shift
        #;;
        -h|--help)
            helpfunction
            exit 0
        ;;
        # Remember that shifting doesn't remove later args from the loop
        -*)
            helpfunction
            exit 1
        ;;
    esac
done
# We don't ever want to pass --ssh!!!
script_args=$(echo $script_args |sed 's/--ssh//')
# shellcheck disable=SC2139
alias kubectl="kubectl $add_kubectl "

mongo_test(){
# mongo testing
echo "Testing MongoDB Pods"
if [ -n "$namespace" ];then
    mongo_ns=$namespace
else
    mongo_ns=$(kubectl get pod --all-namespaces -l nirmata.io/service.name=mongodb --no-headers | awk '{print $1}'|head -1)
fi
mongos=$(kubectl get pod --namespace=$namespace -l nirmata.io/service.name=mongodb --no-headers | awk '{print $1}')
mongo_num=0
mongo_master=""
mongo_error=0
for mongo in $mongos; do
    if kubectl -n $mongo_ns get pod $mongo --no-headers |awk '{ print $2 }' |grep -q '[0-2]/2'; then
        mongo_container="-c mongodb"
    else
        mongo_container=""
    fi
    cur_mongo=$(kubectl -n $mongo_ns exec $mongo $mongo_container -- sh -c 'echo "db.serverStatus()" |mongo' 2>&1|grep  '"ismaster"')
    if [[  $cur_mongo =~ "true" ]];then
        echo "$mongo is master"
        mongo_master="$mongo_master $mongo"
    else
        if [[  $cur_mongo =~ "false" ]];then
            echo "$mongo is a slave"
        else
            error "$mongo is in error (not master or slave)"
            mongo_error=1
            kubectl -n $mongo_ns get pod $mongo --no-headers -o wide
        fi
    fi
    mongo_num=$((mongo_num + 1));
    mongo_stateStr=$(kubectl -n $mongo_ns exec $mongo $mongo_container -- sh -c 'echo "rs.status()" |mongo' 2>&1 |grep stateStr)
    if [[ $mongo_stateStr =~ RECOVERING || $mongo_stateStr =~ DOWN || $mongo_stateStr =~ STARTUP ]];then
        if [[ $mongo_stateStr =~ RECOVERING ]];then warn "Detected recovering Mongodb from this node!"; fi
        if [[ $mongo_stateStr =~ DOWN ]];then error "Detected Mongodb in down state from this node!"; fi
        if [[ $mongo_stateStr =~ STARTUP ]];then warn "Detected Mongodb in startup state from this node!"; fi
        kubectl -n $mongo_ns exec $mongo $mongo_container -- sh -c 'echo "rs.status()" |mongo'
    fi
done
[[ $mongo_num -gt 3 ]] && error "Found $mongo_num Mongo Pods $mongos!!!" && mongo_error=1
[[ $mongo_num -eq 0 ]] && error "Found Mongo Pods $mongo_num!!!" && mongo_error=1
[[ $mongo_num -eq 1 ]] && warn "Found One Mongo Pod"  && mongo_error=1
[ -z $mongo_master ] &&  error "No Mongo Master found!!"  && mongo_error=1
[[ $(echo $mongo_master|wc -w) -gt 1 ]] &&  error "Mongo Masters $mongo_master found!!" && mongo_error=1
[ $mongo_error -eq 0 ] && good "MongoDB passed tests"
}

zoo_test(){
# Zookeeper testing
zoo_error=0
echo "Testing Zookeeper pods"
if [ -n "$namespace" ];then
    zoo_ns=$namespace
else
    zoo_ns=$(kubectl get pod --all-namespaces -l 'nirmata.io/service.name in (zookeeper, zk)' --no-headers | awk '{print $1}'|head -1)
fi
zoos=$(kubectl get pod -n $zoo_ns -l 'nirmata.io/service.name in (zookeeper, zk)' --no-headers | awk '{print $1}')
zoo_num=0
zoo_leader=""
for zoo in $zoos; do
    curr_zoo=$(kubectl -n $zoo_ns exec $zoo -- sh -c "/opt/zookeeper-*/bin/zkServer.sh status" 2>&1|grep Mode)
    if [[  $curr_zoo =~ "leader" ]];then
        echo "$zoo is zookeeper leader"
        zoo_leader="$zoo_leader $zoo"
    else
        if [[  $curr_zoo =~ "follower" ]];then
            echo "$zoo is zookeeper follower"
        else
            if [[  $curr_zoo =~ "standalone" ]];then
                echo "$zoo is zookeeper standalone"
                zoo_leader="$zoo_leader $zoo"
            else
                error "$zoo appears to have failed. (not follower/leader/standalone)"
                kubectl -n $zoo_ns get pod $zoo --no-headers -o wide
                zoo_error=1
            fi
        fi

    fi
    zoo_num=$((zoo_num + 1));
    zoo_df=$(kubectl -n $zoo_ns exec $zoo -- df /tmp/ | awk '{ print $5; }' |tail -1|sed s/%//)
    [[ $zoo_df -gt 50 ]] && error "Found zookeeper volume at ${zoo_df}% usage on $zoo"
done

# This is a crude parse, but it will do.
connected_kaf=$(kubectl exec -it $zoo -n $zoo_ns -- sh -c "echo ls /brokers/ids | /opt/zookeeper/bin/zkCli.sh")
con_kaf_num=0
# shellcheck disable=SC2076
if [[ $connected_kaf =~ '[0, 1, 2]' ]];then
    con_kaf_num=3
fi
# shellcheck disable=SC2076
if [[ $connected_kaf =~ '[0, 1]' ]];then
    con_kaf_num=2
fi
# shellcheck disable=SC2076
if [[ $connected_kaf =~ '[0]' ]];then
    con_kaf_num=1
fi

[[ $zoo_num -gt 3 ]] && error "Found $zoo_num Zookeeper Pods $zoos!!!" && zoo_error=1
[[ $zoo_num -eq 0 ]] && error "Found Zero Zookeeper Pods !!" && zoo_error=1
[[ $zoo_num -eq 1 ]] && warn "Found One Zookeeper Pod." && zoo_error=1
[ -z $zoo_leader ] &&  error "No Zookeeper Leader found!!" && zoo_error=1
[[ $(echo $zoo_leader|wc -w) -gt 1 ]] && warn "Found Zookeeper Leaders $zoo_leader." && zoo_error=1
[ $zoo_error -eq 0 ] && good "Zookeeper passed tests"
if [[ $con_kaf_num -eq 3 ]];then
    good "Found 3 connected Kafkas"
else
    if [[ $con_kaf_num -gt 0 ]];then
        warn "Found $con_kaf_num connected Kafkas"
    else
        error "Found $con_kaf_num connected Kafkas"
    fi
fi
}

kafka_test(){
#  testing
echo "Testing Kafka pods"
if [ -n "$namespace" ];then
    kafka_ns=$namespace
else
    kafka_ns=$(kubectl get pod --all-namespaces -l nirmata.io/service.name=kafka --no-headers | awk '{print $1}'|head -1)
fi
kafkas=$(kubectl get pod -n $kafka_ns -l nirmata.io/service.name=kafka --no-headers | awk '{print $1}')
kaf_num=0
for kafka in $kafkas; do
    echo "Found Kafka Pod $(kubectl -n $kafka_ns get pod $kafka --no-headers)"
    kafka_df=$(kubectl -n $kafka_ns exec $kafka -- df /tmp/ | awk '{ print $5; }' |tail -1|sed s/%//)
    [[ $kafka_df -gt 50 ]] && error "Found Kafka volume at ${kafka_df}% usage on $kafka"
    kaf_num=$((kaf_num + 1));
done
[[ $kaf_num -gt 3 ]] && error "Found $kaf_num Kafka Pods $kafkas!!!" && kaf_error=1
[[ $kaf_num -eq 0 ]] && error "Found Zero Kafka Pods!!" && kaf_error=1
[[ $kaf_num -eq 1 ]] && warn "Found One Kafka Pod." && kaf_error=1
[[ $kaf_error -eq 0 ]] && good "Kafka passed tests"
}

remote_test(){
    command -v kubectl &>/dev/null || error 'No kubectl found in path!!!'
    echo "Starting Cluster Tests"
    # Setup a DaemonSet to test dns on all nodes.
    echo 'apiVersion: extensions/v1beta1
kind: DaemonSet
metadata:
  name: nirmata-net-test-all
spec:
  template:
    metadata:
      labels:
        app: nirmata-net-test-all-app
    spec:
      containers:
        - name: nirmata-net-test-node
          image: nicolaka/netshoot
          command: [ "/bin/sh", "-c", "sleep  100000" ]' >/tmp/nirmata-net-test-all.yml

    namespaces="$(kubectl get ns  --no-headers | awk '{print $1}')"
    for ns in $namespaces;do
            kubectl --namespace=$ns delete ds nirmata-net-test-all --ignore-not-found=true &>/dev/null
    done
    kubectl --namespace=$namespace delete ds nirmata-net-test-all --ignore-not-found=true &>/dev/null
    #echo allns is $allns
    if [ $allns != 1 ];then
        for ns in $namespaces;do
            kubectl --namespace=$ns apply -f /tmp/nirmata-net-test-all.yml &>/dev/null
        done
    else
        namespaces=$namespace
        kubectl --namespace=$namespace apply -f /tmp/nirmata-net-test-all.yml &>/dev/null
    fi
    #echo Testing namespaces $namespaces

    #check for nodes, and kubectl function
    echo
    echo Found the following nodes:
    if ! kubectl get node --no-headers; then
        error 'Failed to contact cluster!!!'
        echo 'Is the master up? Is kubectl configured?'
    fi
    echo

    if kubectl get no -o jsonpath="{.items[?(@.spec.unschedulable)].metadata.name}"|grep .;then
        warn 'Above nodes are unschedulable!!'
    fi

    times=0
    required_pods=$(kubectl get node --no-headers | awk '{print $2}' |grep -c Ready )
    num_ns=$(echo $namespaces |wc -w)
    required_pods=$((required_pods * num_ns))
    #echo required_pods is $required_pods
    echo -n 'Waiting for nirmata-net-test-all pods to start'
    until [[ $(kubectl get pods -l app=nirmata-net-test-all-app --no-headers --all-namespaces|awk '{print $4}' |grep -c Running) -ge $required_pods ]]|| \
      [[ $times = 60 ]];do
        sleep 1;
        echo -n .;
        times=$((times + 1));
    done
    echo

    # Do we have at least as many pods as nodes? (Do we care enough to do a compare node to pod?)
    if [[ $(kubectl -n $namespace get pods -l app=nirmata-net-test-all-app --no-headers |awk '{print $3}' |grep -c Running) -ne \
      $(kubectl get node --no-headers | awk '{print $2}' |grep -c Ready) ]] ;then
        error 'Failed to start nirmata-net-test-all on all nodes!!'
        echo Debugging:
        kubectl get pods -l app=nirmata-net-test-all-app -o wide
        kubectl get node
    fi

    dns_error=0
    for ns in $namespaces;do
        echo Testing $ns namespace
    for pod in $(kubectl -n $ns get pods -l app=nirmata-net-test-all-app --no-headers |grep Running |awk '{print $1}');do
        echo Testing "$(kubectl -n $ns get pods $pod -o wide --no-headers| awk '{print $7}') Namespace $ns"
        if  kubectl exec $pod -- nslookup $DNSTARGET 2>&1|grep -e can.t.resolve -e does.not.resolve -e can.t.find -e No.answer;then
            warn "Can not resolve external DNS name $DNSTARGET on $pod."
            kubectl -n $ns get pod $pod -o wide
            kubectl -n $ns exec $pod -- sh -c "nslookup $DNSTARGET"
            echo
        else
            good "DNS test $DNSTARGET on $pod suceeded."
        fi
        #kubectl -n $ns exec $pod -- nslookup $SERVICETARGET
        if kubectl -n $ns exec $pod -- nslookup $SERVICETARGET 2>&1|grep -e can.t.resolve -e does.not.resolve -e can.t.find -e No.answer;then
            warn "Can not resolve $SERVICETARGET service on $pod"
            echo 'Debugging info:'
            kubectl get pod $pod -o wide
            dns_error=1
            kubectl -n $ns exec $pod -- nslookup $DNSTARGET
            kubectl -n $ns exec $pod -- nslookup $SERVICETARGET
            kubectl -n $ns exec $pod -- cat /etc/resolv.conf
            error "DNS test failed to find $SERVICETARGET service on $pod"
        else
            good "DNS test $SERVICETARGET on $pod suceeded."
        fi
        if [[ $curl -eq 0 ]];then
             if [[ $http -eq 0 ]];then
                 if  kubectl -n $ns exec $pod -- sh -c "if curl --max-time 5 http://$SERVICETARGET; then exit 0; else exit 1; fi" 2>&1|grep -e 'command terminated with exit code 1';then
                     error "http://$SERVICETARGET failed to respond to curl in 5 seconds!"
                 else
                     good "HTTP test $SERVICETARGET on $pod suceeded."
                 fi
             else
                 if  kubectl -n $ns exec $pod -- sh -c "if curl --max-time 5 -k https://$SERVICETARGET; then exit 0; else exit 1; fi" 2>&1|grep -e 'command terminated with exit code 1';then
                     error "https://$SERVICETARGET failed to respond to curl in 5 seconds!"
                 else
                     good "HTTPS test $SERVICETARGET on $pod suceeded."
                 fi
             fi
        fi

    done
    done

    if [[ dns_error -eq 1 ]];then
        warn "DNS issues detected"
        echo 'Additional debugging info:'
        kubectl get svc -n kube-system kube-dns coredns
        kubectl get deployments -n kube-system coredns kube-dns
        echo 'Note you should have either coredns or kube-dns running. Not both.'
    fi

     namespaces="$(kubectl get ns  --no-headers | awk '{print $1}')"
     for ns in $namespaces;do
         kubectl --namespace=$ns delete ds nirmata-net-test-all --ignore-not-found=true &>/dev/null
    done



}

local_test(){
echo "Starting Local Tests"

echo "Checking for swap"
if [[ $(swapon -s | wc -l) -gt 1 ]] ;  then
    if [[ $fix_issues -eq 0 ]];then
        warn "Found swap enabled"
        echo "Applying the following fixes"
        ech 'swapoff -a'
        swapoff -a
        echo "sed -i '/[[:space:]]*swap[[:space:]]*swap/d' /etc/fstab"
        sed -i '/[[:space:]]*swap[[:space:]]*swap/d' /etc/fstab
    else
        error "Found swap enabled!"
    fi
fi

echo "Testing SELinux"
if type sestatus &>/dev/null;then
    if ! sestatus | grep "Current mode" |grep -e permissive -e disabled;then
        warn 'SELinux enabled'
        if [[ $fix_issues -eq 0 ]];then
            echo "Applying the following fixes"
            echo '  sed -i s/^SELINUX=.*/SELINUX=permissive/ /etc/selinux/config'
            sed -i s/^SELINUX=.*/SELINUX=permissive/ /etc/selinux/config
            echo '  setenforce 0'
            setenforce 0
        else
            echo Consider the following changes to disabled SELinux if you are having issues:
            echo '  sed -i s/^SELINUX=.*/SELINUX=permissive/ /etc/selinux/config'
            echo '  setenforce 0'
        fi
    fi
else
    #assuming debian/ubuntu don't do selinux
    if [ -e /etc/os-release ]  &&  ! grep -q -i -e debian -e ubuntu /etc/os-release;then
        warn 'sestatus binary not found assuming SELinux is disabled.'
    fi
fi

#test kernel ip forward settings
if grep -q 0 /proc/sys/net/ipv4/ip_forward;then
        if [[ $fix_issues -eq 0 ]];then
            warn net.ipv4.ip_forward is set to 0
            echo "Applying the following fixes"
            echo '  sysctl -w net.ipv4.ip_forward=1'
            sysctl -w net.ipv4.ip_forward=1
            echo '  echo net.ipv4.ip_forward=1 >> /etc/sysctl.conf'
            echo net.ipv4.ip_forward=1 >> /etc/sysctl.conf
        else
            error net.ipv4.ip_forward is set to 0
            echo Consider the following changes:
            echo '  sysctl -w net.ipv4.ip_forward=1'
            echo '  echo net.ipv4.ip_forward=1 >> /etc/sysctl.conf'
        fi
else
    good ip_forward enabled
fi

if [ ! -e /proc/sys/net/bridge/bridge-nf-call-iptables ];then
    if [[ $fix_issues -eq 0 ]];then
        warn '/proc/sys/net/bridge/bridge-nf-call-iptables does not exist!'
        echo "Applying the following fixes"
        echo '  modprobe br_netfilter'
        modprobe br_netfilter
        echo '  echo "br_netfilter" > /etc/modules-load.d/br_netfilter.conf'
        echo "br_netfilter" > /etc/modules-load.d/br_netfilter.conf
    else
        error '/proc/sys/net/bridge/bridge-nf-call-iptables does not exist!'
        echo 'Is the br_netfilter module loaded? "lsmod |grep br_netfilter"'
        echo Consider the following changes:
        echo '  modprobe br_netfilter'
        echo '  echo "br_netfilter" > /etc/modules-load.d/br_netfilter.conf'
    fi
fi
if grep -q 0 /proc/sys/net/bridge/bridge-nf-call-iptables;then
    if [[ $fix_issues -eq 0 ]];then
        warn "Bridge netfilter disabled!!"
        echo "Applying the following fixes"
        echo '  sysctl -w net.bridge.bridge-nf-call-iptables=1'
        sysctl -w net.bridge.bridge-nf-call-iptables=1
        echo '  echo net.bridge.bridge-nf-call-iptables=1 >> /etc/sysctl.conf'
        echo net.bridge.bridge-nf-call-iptables=1 >> /etc/sysctl.conf
    else
        error "Bridge netfilter disabled!!"
        echo Consider the following changes:
        echo '  sysctl -w net.bridge.bridge-nf-call-iptables=1'
        echo '  echo net.bridge.bridge-nf-call-iptables=1 >> /etc/sysctl.conf'
    fi
else
    good bridge-nf-call-iptables enabled
fi


#TODO check for proxy settings, how, what, why

#test for docker
if ! systemctl is-active docker &>/dev/null ; then
    warn 'Docker service is not active? Maybe you are using some other CRI??'
else
    if docker info 2>/dev/null|grep mountpoint;then
        warn 'Docker does not have its own mountpoint'
        # What is the fix for this???
    else
        good Docker is active
    fi
fi
if type kubelet &>/dev/null;then
    #test for k8 service
    echo Found kubelet running local kubernetes tests
    if ! systemctl is-active kubelet &>/dev/null;then
        error 'Kubelet is not active?'
    else
        good Kublet is active
    fi
    if ! systemctl is-enabled kubelet &>/dev/null;then
        if [[ $fix_issues -eq 0 ]];then
            echo "Applying the following fixes"
            echo systectl enable kubelet
            systectl enable kubelet
        else
            error 'Kubelet is not set to run at boot?'
        fi
    else
        good Kublet is enabled at boot
    fi
else
    if [ -e /etc/systemd/system/nirmata-agent.service ];then
        echo Found nirmata-agent.service testing Nirmata agent
        test_agent
    else
        error No Kubelet or Nirmata Agent!!!
    fi
fi
    if [ ! -e /opt/cni/bin/bridge ];then
        warn '/opt/cni/bin/bridge not found is your CNI installed?'
    fi

if [ ! -e /opt/cni/bin/bridge ];then
    warn '/opt/cni/bin/bridge not found is your CNI installed?'
fi

}

test_agent(){
echo Test Nirmata Agent
if systemctl is-active nirmata-agent &>/dev/null ; then
    good Nirmata Agent is running
else
    error Nirmata Agent is not running
fi
if systemctl is-enabled nirmata-agent &>/dev/null ; then
    good Nirmata Agent is enabled at boot
else
    error Nirmata Agent is not enabled at boot
fi
if docker ps |grep -q -e nirmata/nirmata-host-agent;then
    good Found nirmata-host-agent
else
    error nirmata-host-agent is not running!
fi
if docker ps |grep -q -e "hyperkube proxy";then
    good Found hyperkube proxy
else
    error Hyperkube proxy is not running!
fi
if docker ps --no-trunc|grep -q -e 'hyperkube kubelet' ;then
    good Found hyperkube kubelet
else
    error Hyperkube kubelet is not running!
fi
if docker ps |grep -q -e /opt/bin/flanneld ;then
    good Found flanneld
else
    error Flanneld is not running!
fi
# How do we determine if this is the master?
#grep -e /usr/local/bin/etcd -e /nirmata-kube-controller -e /metrics-server -e "hyperkube apiserver"
#if docker ps |grep -q -e nirmata/nirmata-kube-controller;then
#    good Found nirmata-kube-controller
#else
#    error nirmata-kube-controller is not running!
#fi
#if docker ps |grep -q -e /metrics-server;then
#    good Found Metrics container
#else
#    error Metrics container is not running!
#fi
}

#start main script
if [ ! -z $logfile ];then
    $0 $script_args 2>&1 |tee $logfile
    return_code=$?
    # Reformat the log file for better reading
    #shellcheck disable=SC1012
    sed -i -e 's/\x1b\[[0-9;]*m//g' -e 's/$'"/$(echo \\\r)/" $logfile
    exit $return_code
fi
if [[ $nossh -eq 1 ]];then
    if [[ ! -z $ssh_hosts ]];then
        for host in $ssh_hosts; do
            echo Testing host $host
            cat $0 | ssh $host bash -c "cat >/tmp/k8_test_temp.sh ; chmod 755 /tmp/k8_test_temp.sh; /tmp/k8_test_temp.sh $script_args --nossh ; rm /tmp/k8_test_temp.sh"
            echo
            echo
        done
    fi
else
    if [[ $email -eq 0 ]];then
        script_args=$(echo $script_args |sed 's/--email//')
        [ -z $logfile ] && logfile="/tmp/k8_test.$$"
        [ -z $EMAIL_USER ] && EMAIL_USER=""
        [ -z $EMAIL_PASSWD ] && EMAIL_PASSWD=""
        #[ -z $TO ] && error "No TO address given!!!" && exit 1
        [ -z $FROM ] && FROM="k8@nirmata.com" && warn "You provided no From address using $FROM"
        [ -z $SUBJECT ] && SUBJECT="K8 test script error" && warn "You provided no Subject using $SUBJECT"
        #[ -z $SMTP_SERVER ] && error "No smtp server given!!!" && exit 1
        echo
        sleep 1
        $0 $script_args 2>&1 |tee $logfile
        if [[ ${PIPESTATUS[0]} -ne 0 || ${alwaysemail} -eq 0 ]]; then
            # Reformat the log file for better reading
            # shellcheck disable=SC1012
            sed -i -e 's/\x1b\[[0-9;]*m//g' -e 's/$'"/$(echo \\\r)/" $logfile
            BODY=$(cat $logfile)
            if type -P "sendEmail" &>/dev/null; then
                if [ -n "$PASSWORD" ];then
                    #echo sendEmail -t "$TO" -f "$FROM" -u \""$SUBJECT"\" -s "$SMTP_SERVER" "$EMAIL_OPTS"
                    sendEmail -t "$TO" -f "$FROM" -u \""$SUBJECT"\" -s "$SMTP_SERVER" "$EMAIL_OPTS" -m \""${BODY}"\"
                else
                    #echo sendEmail -t "$TO" -f "$FROM" -u \""$SUBJECT"\" -s "$SMTP_SERVER" -xu "$EMAIL_USER" -xp "$EMAIL_PASSWD" "$EMAIL_OPTS"
                    sendEmail -t "$TO" -f "$FROM" -u \""$SUBJECT"\" -s "$SMTP_SERVER" -xu "$EMAIL_USER" -xp "$EMAIL_PASSWD" "$EMAIL_OPTS" -m \""${BODY}"\"
                fi
            else
                docker run $sendemail $TO $FROM "$SUBJECT" "${BODY}" $SMTP_SERVER "$EMAIL_USER" "$EMAIL_PASSWD" "$EMAIL_OPTS"
            fi
            #If they named it something else don't delete
            rm -f /tmp/k8_test.$$
            exit 1
        fi
        # Reformat the log file for better reading
        # shellcheck disable=SC1012
        sed -i -e 's/\x1b\[[0-9;]*m//g' -e 's/$'"/$(echo \\\r)/" $logfile
        #If they named it something else don't delete
        rm -f /tmp/k8_test.$$
        exit 0
    fi
    if [[ $run_local -eq 0 ]];then
        local_test
    fi

    if [[ $run_remote -eq 0 ]];then
        remote_test
    fi

    if [[ $run_mongo -eq 0 ]];then
        mongo_test
    fi

    if [[ $run_zoo -eq 0 ]];then
        zoo_test
    fi

    if [[ $run_kafka -eq 0 ]];then
        kafka_test
    fi

    if [ $error != 0 ];then
        error "Test completed with errors!"
        exit $error
    fi
    if [ $warn != 0 ];then
        warn "Test completed with warnings."
        if [ $warnok != 0 ];then
            exit 2
        fi
    fi
    echo -e  "\e[32mTesting completed without errors or warning\e[0m"
    exit 0
fi
