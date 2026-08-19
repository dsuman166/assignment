terraform {
  required_version = ">= 1.5.0"
  required_providers {
    kind = {
      source  = "tehcyx/kind"
      version = "0.9.0"
    }
  }
}

provider "kind" {}

resource "kind_cluster" "default" {
  name           = "assignment-cluster"
  wait_for_ready = true

  kind_config {
    kind        = "Cluster"
    api_version = "kind.x-k8s.io/v1alpha4"

    node {
      role = "control-plane"

      # Expose NodePort 30080 on host port 8080 so the web app is reachable
      # from the host machine without needing kubectl port-forward.
      extra_port_mappings {
        container_port = 30080
        host_port       = 8080
        protocol        = "TCP"
      }

      kubeadm_config_patches = [
        "kind: InitConfiguration\nnodeRegistration:\n  kubeletExtraArgs:\n    node-labels: \"ingress-ready=true\"\n"
      ]
    }
  }
}

output "kubeconfig_path" {
  value = kind_cluster.default.kubeconfig_path
}

output "cluster_name" {
  value = kind_cluster.default.name
}
