apiVersion: v1alpha1
kind: Layer2VIPConfig
name: 10.0.5.200
link: eno1
---
apiVersion: v1alpha1
kind: LinkConfig
name: eno1
addresses:
  - address: {{ .Node.IP }}/24
routes:
  - gateway: 10.0.5.1
