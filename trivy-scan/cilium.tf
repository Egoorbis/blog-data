resource "helm_release" "cilium" {
  name       = "cilium"
  repository = "https://helm.cilium.io/"
  chart      = "cilium"
  version    = "1.16.6"
  namespace  = "kube-system"

  set {
    name  = "aksbyocni.enabled"
    value = "true"
  }
  set {
    name  = "nodeinit.enabled"
    value = "true"
  }
  set {
    name  = "ipam.operator.clusterPoolIPv4PodCIDRList"
    value = "192.168.0.0/16"
  }
  set {
    name  = "hubble.relay.enabled"
    value = "true"
  }
}
