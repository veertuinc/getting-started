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
1. Install the **[Anka Virtualization and CLI package, then activate your license.](https://ankadocs.veertu.com/docs/anka-cli/installation/#install-the-anka-cli)** with `./ANKA/install-anka-virtualization.bash ${LICENSE}`.
2. Install the **Anka Build Cloud Controller & Registry** with `./ANKA/install-build-cloud-on-mac.bash`.
3. Now generate your [Template and Tags](https://ankadocs.veertu.com/docs/getting-started/creating-your-first-vm/#understanding-vm-templates-tags-and-disk-usage) with `./ANKA/create-template.bash`.

URLs and ports you can expect:

- Controller: http://anka.controller:8090
- Registry:   http://anka.registry:8091
- Jenkins:    http://anka.jenkins:8092

At this point, you can try [starting a VM instance from the Anka Build Cloud UI.](https://ankadocs.veertu.com/docs/getting-started/macos/#step-4-start-a-vm-instance-using-the-controller-ui)

---

## ANKA (`./ANKA`)

### `install-anka-virtualization.bash`

- Running this script will install the Anka Virtualization package/CLI onto the current machine.

### `install-build-cloud-on-mac.bash`

- Running this script will download and install the Anka Build Cloud Controller & Registry onto the current machine.

### `create-template.bash`

> [Understanding VM templates, Tags, and Disk Usage](https://ankadocs.veertu.com/docs/getting-started/creating-your-first-vm/#understanding-vm-templates-tags-and-disk-usage)

- Running this script will guide you through downloading Apple's macOS installer and then use it to create your first VM Template.
- Without any arguments, the script will guide you through downloading a specific version of the macOS installer .app. 
- If the first argument is an **absolute* path to your installer .app, the script will not use the guided downloader: (`./ANKA/create-template.bash "/Applications/Install macOS Catalina.app"`).

### `create-tags.bash`

> `create-template.bash` will run this script once the Template is created.

- Running this script will generate a Tag for the VM Template

---

# CI Plugins and Integrations

- [Jenkins](#jenkins-jenkins)

## [Jenkins](https://ankadocs.veertu.com/docs/anka-build-cloud/ci-plugins/jenkins/) (`./JENKINS`)

### `create-jenkins-docker.bash`

- Running this script will start a Jenkins container and configure it to run on http://anka.jenkins:8092. It will install all of the necessary plugins and example Jobs that use [Static and Dynamic Labels](https://ankadocs.veertu.com/docs/anka-build-cloud/ci-plugins/jenkins/#install-and-configure-the-anka-plugin-in-jenkins).

---

## GitLab (`./GITLAB`)

Coming soon!

---

## Buildkite (`./BUILDKITE`)

Coming soon!

---

## TeamCity (`./TEAMCITY`)

Coming soon!

---