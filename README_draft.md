## To be polished

helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx --create-namespace \
  --set controller.service.type=NodePort \
  --set controller.service.nodePorts.http=30080 \
  --set controller.service.nodePorts.https=32438 \
  --set controller.ingressClass=nginx \
  --set controller.ingressClassResource.name=nginx