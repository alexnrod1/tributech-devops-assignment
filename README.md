## Introduction
This repo contains a single helm chart that set up an environment as per requirements https://github.com/tributech-solutions/tributech-devops-assignment

## Concept and Design:
Postulates:
- reuse 3rd party helm charts where feasible, and use latest versions
- strive for simplicity
- automate as much as possible (without being obsessed though)

The app is supposed to run on a k3s cluster.

## Network
1. It is supposed that setup is running on a VM and is exposed outside via NodePort.
2 node ports are used:
- http: 30080
- https: 32438

2. Nginx resides in a dedicated namespace `ingress-nginx`, feel free to use any you prefer.
3. Only http/https nodes are exposed to outside
4. https is used for keyCloak and website only
5. SSL termination is done on Ingress level, traffic goes to and between pods unencrypted

## Tradeoffs
- Security vs Speed: No k8s secrets/env variables are used for passwords and sensitive strings, keyCloak admin panel is exposed

- 3rd party helm chart vs Speed & Configurability & Predictability: Unfortunately, I could not make use of the Bitnami keyCloak due to certain ambiguity In documentation when it comes reverse proxy setup
- Reusability vs Reasonability: Overrides in helm release are almost not used.

## Testing

### Assumptions
You have ubuntu VM with OS > 22.04
You have ssh access under root
Git is single installed tool

### ⚠️ When you stick with the suggested Node ports 30080 and 32438
On the VM, run:
```
mkdir git
cd git
git clone https://github.com/alexnrod1/tributech-devops-assignment.git
cd tributech-devops-assignment/deploy
chmod +x spin-up-environment.sh
./spin-up-environment.sh
```
This will setup k3s, docker and build Website docker file.

Perform next steps to install nginx ingress controller:
```
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update
helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx --create-namespace \
  --set controller.service.type=NodePort \
  --set controller.service.nodePorts.http=30080 \
  --set controller.service.nodePorts.https=32438 \
  --set controller.ingressClass=nginx \
  --set controller.ingressClassResource.name=nginx
```
Execute below command to point to the Kubernetes configuration file used by k3s:
```
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
```

Then spin up the app wih helm:
```
cd /root/git/tributech-devops-assignment/helm-chart/tributech-app
helm install tributech-app .
```

It's going to take 3-4 mins to configure, mainly due to configuration of pgadmin and keyCloak.
Run `kubectl get pods` to check the status, all Pods should have Running status, and the keyCloak config cli job mus have Completed status

Make sure your hosts file contains records for below domains (134.122.71.39 is the IP address of the VM. When no VM is used, set IP to 127.0.0.1):
```
134.122.71.39 pgadmin.local
134.122.71.39 website.local
134.122.71.39 keycloak.local
```

As a result, you should be able to access below resources on your browser:
- https://website.local:32438/
- https://keycloak.local:32438/admin/master/console
- http://pgadmin.local:30080/

To authenicate on the Web UI, use below credentials:

login: `angular-user`
password: `B2qazwe1`

You will be asked for setting up email, fist name and last name for the 1st time.

✅As a result, you should see "Is Authenicated: true"

### ⚠️ When you use custom Node Ports for http and https

Specify your **https** NodePort input parameter when executing the spin-up-environment.sh script.
For instance, when your https port is 33333, run:
```
mkdir git
cd git
git clone https://github.com/alexnrod1/tributech-devops-assignment.git
cd tributech-devops-assignment/deploy
chmod +x spin-up-environment.sh
./spin-up-environment.sh 33333
```
Then override input parameters when running Helm release install.
Below command assumes you have 33333 https and 33334 http:
```
cd /root/git/tributech-devops-assignment/helm-chart/tributech-app
helm install --install tributech-app . \
  --set global.ingress.httpNodePort=33334 \
  --set global.ingress.httpsNodePort=33333
```

✅As a result, you should be able to access below resources on your browser:
- https://website.local:33333/
- https://keycloak.local:33334/admin/master/console
- http://pgadmin.local:33334/

Proceed the same actions to authenticate.