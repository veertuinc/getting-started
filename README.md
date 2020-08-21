# Anka Getting Started Resources

### [Getting Started Documentation](https://ankadocs.veertu.com/docs/getting-started/)

This repo contains various scripts for setting up and testing Anka software on your local Apple machine.

## How to use this repo

> You can set the ENV $DEBUG to true to see verbose execution output

### Important Considerations

- Running everything you need on a single machine can be resource intensive. We highly recommend having a modern Apple machine.
- These scripts are written on macOS Catalina (10.15).
- Each script is idempotent and running them a second time will clean up/uninstall the environment before running.
- Most of these scripts will prompt for the sudo password at some point in their execution. While it's possible to run the Anka CLI as a non-root user, the **Anka Build Cloud** runs anka commands as root. Executing the Anka CLI as a non-sudo user will only cause confusion or waste disk space.

### Requirements

- An Apple machine
- Docker Desktop installed on that same machine
- [Homebrew](https://brew.sh/)

### Initial Setup

Before integrating Anka with your CI, you need to install and configure the **Anka Virtualization CLI** and **Build Cloud Controller & Registry**.

1. Obtain your trial license from https://veertu.com/getting-started-anka-trials/
1. Install the **[Anka Virtualization CLI package, then activate your license](https://ankadocs.veertu.com/docs/anka-cli/installation/#install-the-anka-cli)** with `./ANKA_BUILD_CLOUD/install-anka-build-virtualization-on-mac.bash`.
2. Install the **Anka Build Cloud Controller & Registry** with `./ANKA_BUILD_CLOUD/install-anka-build-controller-and-registry-on-mac.bash`.
3. Now generate your [Template and Tags](https://ankadocs.veertu.com/docs/getting-started/creating-your-first-vm/#understanding-vm-templates-tags-and-disk-usage) with `./ANKA_BUILD_CLOUD/create-template.bash`.

At this point, you can try [starting a VM instance from the Anka Build Cloud UI.](https://ankadocs.veertu.com/docs/getting-started/macos/#step-4-start-a-vm-instance-using-the-controller-ui)

URLs and ports you can expect:

- Controller: http://anka.controller:8090
- Registry:   http://anka.registry:8091
- Jenkins:    http://anka.jenkins:8092
- TeamCity:   http://anka.teamcity:8094

---

## ANKA (`./ANKA_BUILD_CLOUD`)

### `install-anka-build-virtualization.bash`

- Running this script will install the latest Anka Virtualization package/CLI onto the current machine.
- If the first argument is an **absolute* path to your installer package, the script will not use the guided downloader: (`./ANKA_BUILD_CLOUD/install-anka-virtualization.bash "/Users/myUserName/Downloads/Anka-2.1.1.111.pkg"`).
- If the first argument is `--uninstall`, it will only remove the existing install.

### `install-build-controller-and-registry-on-mac.bash`

- Running this script will download and install the latest Anka Build Cloud Controller & Registry onto the current machine.
- If the first argument is an **absolute* path to your installer package, the script will not use the guided downloader: (`./ANKA_BUILD_CLOUD/install-build-cloud-on-mac.bash "/Users/myUserName/Downloads/AnkaControllerRegistry-1.4.0-8a38607d.pkg"`).
- If the first argument is `--uninstall`, it will only remove the existing install.

### `create-template.bash`

> [Understanding VM templates, Tags, and Disk Usage](https://ankadocs.veertu.com/docs/getting-started/creating-your-first-vm/#understanding-vm-templates-tags-and-disk-usage)

- Running this script will guide you through downloading Apple's macOS installer and then use it to create your first VM Template.
- Without any arguments, the script will guide you through downloading a specific version of the macOS installer .app. 
- If the first argument is an **absolute* path to your installer .app, the script will not use the guided downloader: (`./ANKA_BUILD_CLOUD/create-template.bash "/Applications/Install macOS Catalina.app"`).

### `create-tags.bash`

> `create-template.bash` will run this script once the Template is created.

- Running this script will generate a Tag for the VM Template

### `generate-certs.bash`

- Running this script will generate all of the certificates you'll need to enable Certificate Authentication. By default, it will assume you are running everything on the same machine (127.0.0.1).

---

# CI Plugins and Integrations

- [Jenkins](#jenkins-jenkins)
- [TeamCity](#teamcity-teamcity)

---

> **CI/CD platform scripts require that you first peform the [Initial Setup](#initial-setup) steps**

---

## [Jenkins](https://ankadocs.veertu.com/docs/ci-plugins-and-integrations/jenkins/) (`./JENKINS`)

### `install-jenkins-on-docker.bash`

> **Be sure to generate the required VM Tag using `./ANKA_BUILD_CLOUD/create-tags.bash 10.15.5 --jenkins`**

- Running this script will start a Jenkins container and configure it to run on http://anka.jenkins:8092. It will install all of the necessary plugins and example Jobs that use [Static and Dynamic Labels](https://ankadocs.veertu.com/docs/ci-plugins-and-integrations/jenkins/#install-and-configure-the-anka-plugin-in-jenkins).

---

## [TeamCity](https://ankadocs.veertu.com/docs/ci-plugins-and-integrations/teamcity/) (`./TEAMCITY`)

### `install-teamcity-server-on-docker.bash`

> **Be sure to generate the required VM Tag using `./ANKA_BUILD_CLOUD/create-tags.bash 10.15.5 --teamcity`**

- Running this script will setup TeamCity server, plugins, and a testing project within a docker container.
- If the first argument is `--uninstall`, it will only remove the existing install.

---

## GitLab (`./GITLAB`)

> **Be sure to generate the required VM Tag using `./ANKA/create-tags.bash 10.15.5 --gitlab`**

### `install-gitlab-on-docker.bash`

- Running this script will setup GitLab and a testing project within a docker container, then two other containers with a shared and project specific [anka-gitlab-runner](https://github.com/veertuinc/gitlab-runner).
- If the first argument is `--uninstall`, it will only remove the existing install.

### `install-and-run-anka-gitlab-runner-on-docker.bash`

- Running this script will setup two gitlab runner containers that are registered as a shared and project specific runner with your gitlab instance.
- If the first argument is `--uninstall`, it will only remove the existing containers

### `install-and-run-native-ank-gitlab-runner-on-mac.bash`

- Running this script will setup 
- If the first argument is `--uninstall`, it will only remove the existing containers

---

## Buildkite (`./BUILDKITE`)

Coming soon!

---