This is the Nirmata test script.  It will check either your local system for Kubernetes compatiblity, or perform a basic health check of your kubernetes cluster.

It has 2 basic modes:

Local testing:

./k8_test.sh --local

Cluster testing (requires working kubectl):

./k8_test.sh --cluster

There are also a host of other features such as email support, and ssh support.  See --help for more info.

Examples:

Run local tests on remote host.

./k8_test.sh --local --ssh "user@host.name user2@host2.name2"

Email on error (Note using gmail requires an app password)

./k8_test.sh --cluster --email --to testy@nirmata.com --smtp smtp.gmail.com:587  --user sam.silbory --passwd 'foo!foo' 
