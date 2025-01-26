# image factory

you don't do any of this bc you use talhelper
https://budimanjojo.github.io/talhelper/latest/guides/#adding-talos-extensions-and-kernel-arguments

Extensions seen in longhorn.yaml can be found in the image factory ui
https://factory.talos.dev/

```
➜ curl -X POST --data-binary @longhorn.yaml https://factory.talos.dev/schematics
{"id":"c527b6b20fb22847304656677e9bd4c4055dfcce95f3385da5db80e35f5fa1dc"}

This would be used in the image url below

```
factory.talos.dev/installer/c527b6b20fb22847304656677e9bd4c4055dfcce95f3385da5db80e35f5fa1dc:v${some_talos_version}
```

This could be patched in like below

```
machine:
  install:
    image: factory.talos.dev/installer/c527b6b20fb22847304656677e9bd4c4055dfcce95f3385da5db80e35f5fa1dc:v1.6.5
```
