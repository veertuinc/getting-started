# Anka Getting Started Resources

## [Getting Started Documentation](https://docs.veertu.com/anka/intel/getting-started/)

This repo contains various scripts for setting up and testing Anka software on your local Apple machine.

## How to use this repo

> You can set the ENV $DEBUG to true to see verbose execution output

### Important Considerations

- Running everything you need on a single machine can be resource intensive. We highly recommend having a modern Apple machine.
- Each script is idempotent and running them a second time will clean up/uninstall the environment before running.
- Most of these scripts will prompt for the sudo password at some point in their execution. While it's possible to run the Anka CLI as a non-root user, the **Anka Build Cloud** runs anka commands as root. Executing the Anka CLI as a non-sudo user will only cause confusion or waste disk space.

### Requirements

- An Apple machine
- Docker Desktop installed on that same machine
    - `Preferences > Resources > Advanced`: Ensure that you have given plenty of memory and cpu 
- [Homebrew](https://brew.sh/)

### Initial Setup

Before integrating Anka with your CI, you need to install and configure the **Anka Virtualization CLI** and **Build Cloud Controller & Registry**.

1. Obtain your trial license from https://veertu.com/getting-started-anka-trials/
1. Install the **[Anka Virtualization CLI package, then activate your license](https://docs.veertu.com/anka/intel/getting-started/installing-the-anka-virtualization-package/)** with `./install-anka-virtualization-on-mac.bash`.
2. Install the **Anka Build Cloud Controller & Registry** with `./ANKA_BUILD_CLOUD/install-anka-build-controller-and-registry-on-mac.bash`.
3. Now generate your [Template and Tags](https://docs.veertu.com/anka/intel/getting-started/creating-your-first-vm/#anka-build-license--cloud-understanding-vm-templates-tags-and-disk-usage) with `./create-vm-template.bash`.

At this point, you can try [starting a VM instance from the Anka Build Cloud UI.](https://docs.veertu.com/anka/intel/anka-build-cloud/working-with-controller-and-api/#instances-view)

URLs and ports you can expect:

- Controller: http://anka.controller:8090
- Registry:   http://anka.registry:8089
- Jenkins:    http://anka.jenkins:8092
- GitLab:     http://anka.gitlab:8093
- TeamCity:   http://anka.teamcity:8094

---

### [`install-anka-virtualization-on-mac.bash`](./install-anka-virtualization-on-mac.bash)

- Running this script will install the latest Anka Virtualization package/CLI onto the current machine.
- If the first argument is an **absolute* path to your installer package, the script will not use the guided downloader: (`./install-anka-virtualization.bash "/Users/myUserName/Downloads/Anka-2.1.1.111.pkg"`).
- If the first argument is `--uninstall`, it will only remove the existing install.

### [`create-vm-template.bash`](./create-vm-template.bash)

> [Understanding VM templates, Tags, and Disk Usage](https://docs.veertu.com/anka/intel/getting-started/creating-your-first-vm/#understanding-vm-templates-tags-and-disk-usage)

- Running this script will download the latest macOS installer to create a VM with. You can also specify `MACOS_VERSION="12.2.1"` to target a specific version.
- The downsides of this script is that it relies on shared.bash in the repo, so be sure to clone the whole repo. You also need to override `ANKA_BASE_VM_TEMPLATE_UUID_INTEL` as it will set the same UUID forcibly for any VMs the script creates. Since you may want to use this script anytime you create a new macOS version, obtain and set a new/unique UUID with `ANKA_BASE_VM_TEMPLATE_UUID_INTEL=$(anka create tmp-gss &>/dev/null;anka show tmp-gss uuid | xargs;anka delete --yes tmp-gss) ./create-vm-template.bash`

### [`create-vm-template-tags.bash`](./create-vm-template-tags.bash)

> `create-vm-template.bash` will run this script once the Template is created.

- ARG 1 must be the name of the VM to build layers/tags for.
- You can use `TAG_FLAGS="--jenkins" ./create-vm-. . .` to tell the tag creation process to prepare the jenkins template/tag.
- Running this script will generate several foundational/recommended Tags for the VM Template created with `create-vm-template.bash`.

---

## ANKA BUILD CLOUD [(`./ANKA_BUILD_CLOUD`)](./ANKA_BUILD_CLOUD)

### [`install-anka-build-controller-and-registry-on-mac.bash`](./ANKA_BUILD_CLOUD/install-anka-build-controller-and-registry-on-mac.bash)

- Running this script will download and install the latest Anka Build Cloud Controller & Registry onto the current machine.
- If the first argument is an **absolute* path to your installer package, the script will not use the guided downloader: (`./ANKA_BUILD_CLOUD/install-anka-build-controller-and-registry-on-mac.bash "/Users/myUserName/Downloads/AnkaControllerRegistry-1.4.0-8a38607d.pkg"`).
- If the first argument is `--uninstall`, it will only remove the existing install.

### [`install-anka-build-controller-and-registry-on-docker.bash`](./ANKA_BUILD_CLOUD/install-anka-build-controller-and-registry-on-docker.bash)

- Running this script will download and install the latest Anka Build Cloud Controller & Registry onto your machine using docker + docker-compose.
- If the first argument is an **absolute* path to your installer package, the script will not use the guided downloader: (`./ANKA_BUILD_CLOUD/install-anka-build-controller-and-registry-on-docker.bash "/Users/myUserName/Downloads/anka-controller-registry-1.11.1-1df83172.tar.gz"`).
- If the first argument is `--uninstall`, it will only remove the existing install.

### [`generate-certs.bash`](./ANKA_BUILD_CLOUD/generate-certs.bash)

- Running this script will generate all of the certificates you'll need to enable Certificate Authentication. By default, it will assume you are running everything on the same machine (127.0.0.1).

## ANKA BUILD CLOUD > KUBERNETES [(`./ANKA_BUILD_CLOUD/KUBERNETES`)](./ANKA_BUILD_CLOUD/KUBERNETES)

> **These scripts should be executed in the order they're shown in this readme**

> These scripts can be repurposed for your own kubernetes cluster and are useful to see the minimum requirements for High Availability

> They are also very resource intensive, so if you don't at least have 10vCPUs and 16GB memory, we don't suggest running it locally

### [`install-docker-minikube.bash`](./ANKA_BUILD_CLOUD/KUBERNETES/install-docker-minikube.bash)

- Running this script will start a single kubernetes/minikube node with a third of the available resources on your machine.
- If the first argument is `--uninstall`, it will only remove the existing install.

### [`deploy-namespace.bash`](./ANKA_BUILD_CLOUD/KUBERNETES/deploy-namespace.bash)

- Running this script will setup a context and namespace of "anka" so that if you already have minikube setup, you're not potentially impacting it.
- If the first argument is `--uninstall`, it will only remove the existing install.

### [`deploy-etcd.bash`](./ANKA_BUILD_CLOUD/KUBERNETES/deploy-etcd.bash)

- Running this script will setup a 4 pod etcd cluster.
- If the first argument is `--uninstall`, it will only remove the existing install.

### [`deploy-build-cloud.bash`](./ANKA_BUILD_CLOUD/KUBERNETES/deploy-build-cloud.bash)

- Running this script will setup a 2 pod Anka Build Cloud cluster, each pod containing a controller and also a registry pod.
- If the first argument is `--uninstall`, it will only remove the existing install.

> To check the service and pod health, use `kubectl get svc && kubectl get pods -o wide`

Once the Kubernetes setup looks healthy, you'll need to run `minikube tunnel --cleanup; minikube tunnel` in your terminal to make the service ports available on 127.0.0.1 and therefore http://anka.controller:8090.

> Registry data is not stored on the host and will be lost should you delete your minikube container

> To completely remove the minikube node and all other items, run `./deploy-etcd.bash --uninstall && ./deploy-build-cloud.bash --uninstall && ./deploy-namespace.bash --uninstall && minikube delete`

---

## AWS [(`./AWS`)](./AWS)

**These scripts require a locally configured AWS account, ssh key setup in the region, and proper permissions added to your user in IAM. You'll need the ability to create/modify/delete security groups, create/modify/describe/delete instances, create/modify/describe/delete dedicated machines, create/assign/describe/delete elastic IPs, and describe availability zones.**

> [Documentation](https://docs.veertu.com/anka/intel/getting-started/aws-ec2-mac/)

### [`prepare-build-cloud.bash`](./AWS/prepare-build-cloud.bash)

- Running this script will create everything necessary inside of AWS to run an Anka Build Cloud. This includes a security group, elastic IP, etc.
- **Required before running `prepare-anka-node.bash`**
- If the first argument is `--delete`, it will only remove the instance and other items needed for the build cloud.

### [`prepare-anka-node.bash`](./AWS/prepare-anka-node.bash)

> Requires you first run `prepare-build-cloud.bash`. Otherwise, you need to set several necessary environment variables before execution. These ENVs can be found in the script under the comment `# Collect all existing ids and instances`.

- Running this script will create everything necessary inside of AWS to run an EC2 Mac instance. You’ll be prompted for the Anka license to use if the `ANKA_LICENSE` env variable is not set.
- By default, it will create a mac1.metal dedicated and instance type. If you wish to use the mac2.metal, simply set `AWS_BUILD_CLOUD_MAC_INSTANCE_TYPE="mac2.metal"` when executing the script.
- If the first argument is `--delete`, it will disjoin the node from the controller, remove the anka license, and terminate the instance. **You need to release the dedicated host manually.**

---

# CI Plugins and Integrations

- [Jenkins](#jenkins-jenkins)
- [GitLab](#gitlab-gitlab)
- [TeamCity](#teamcity-teamcity)
- [Github Actions](https://docs.veertu.com/anka/intel/ci-plugins-and-integrations/github-actions/)
- [Buildkite](https://docs.veertu.com/anka/intel/ci-plugins-and-integrations/buildkite/)

---

> **CI/CD platform scripts require that you first peform the [Initial Setup](#initial-setup) steps**

---

## [Jenkins](https://docs.veertu.com/anka/intel/ci-plugins-and-integrations/jenkins/) [(`./JENKINS`)](./JENKINS)

### [`install-jenkins-on-docker.bash`](./JENKINS/install-jenkins-on-docker.bash)

> **Be sure to generate the required VM Tag using `./create-vm-template-tags.bash 10.15.5 --jenkins`**

- Running this script will start a Jenkins container and configure it to run on http://anka.jenkins:8092. It will install all of the necessary plugins and example Jobs that use [Static and Dynamic Labels](https://docs.veertu.com/anka/intel/ci-plugins-and-integrations/jenkins/#install-and-configure-the-anka-plugin-in-jenkins).

---

## [TeamCity](https://docs.veertu.com/anka/intel/ci-plugins-and-integrations/teamcity/) [(`./TEAMCITY`)](./TEAMCITY)

### [`install-teamcity-server-on-docker.bash`](./TEAMCITY/install-teamcity-server-on-docker.bash)

> **Be sure to generate the required VM Tag using `./create-vm-template-tags.bash 10.15.5 --teamcity`**

- Running this script will setup TeamCity server, plugins, and a testing project within a docker container.
- If the first argument is `--uninstall`, it will only remove the existing install.

---

## [GitLab](https://docs.veertu.com/anka/intel/ci-plugins-and-integrations/gitlab/) [(`./GITLAB`)](./GITLAB)

> **Be sure to generate the required VM Tag using `./create-vm-template-tags.bash 10.15.5 --gitlab`**

### [`install-gitlab-on-docker.bash`](./GITLAB/install-gitlab-on-docker.bash)

- Running this script will setup GitLab and a testing project within a docker container, then two other containers with a shared and project specific [anka-gitlab-runner](https://github.com/veertuinc/gitlab-runner).
- If the first argument is `--uninstall`, it will only remove the existing install.

> There is a known issue with running this on macOS Docker Desktop that causes "too many open files"/500 errors after a few jobs have run: https://gitlab.com/gitlab-org/gitlab/-/issues/255992

### [`install-gitlab-runner-and-custom-executor-on-docker.bash`](./GITLAB/install-gitlab-runner-and-custom-executor-on-docker.bash)

- Running this script sets up a Gitlab Runner (at the latest version) with the [Anka Cloud Gitlab Executor](https://github.com/veertuinc/anka-cloud-gitlab-executor) attached.
- If the first argument is `--uninstall`, it will only remove the existing install.
- Use A`NKA_CLOUD_CONTROLLER_URL="" ./. . .` to change the controller address the runner will comunicate with. It defaults to `host.docker.internal`.

<!-- ### [`install-and-run-anka-gitlab-runners-on-docker.bash`](./GITLAB/install-and-run-anka-gitlab-runners-on-docker.bash)

- Running this script will setup two gitlab runner containers that are registered as a shared and project specific runner with your gitlab instance.
- If the first argument is `--uninstall`, it will only remove the existing containers

### [`install-and-run-anka-gitlab-runners-on-mac.bash`](./GITLAB/install-and-run-anka-gitlab-runners-on-mac.bash)

- Running this script will setup two gitlab runners that are registered as a shared and project specific runner with your gitlab instance.
- If the first argument is `--uninstall`, it will only remove the existing containers -->

---

# Monitoring
## Prometheus Exporter [(`./PROMETHEUS`)](./PROMETHEUS)

[Prometheus](https://prometheus.io/docs/introduction/overview/) is a powerful monitoring and alerting toolkit. You can use it to store Anka Controller, Registry, VM metrics to build out or integrating into existing graphing tools like [Grafana](https://grafana.com/).

The scripts included in this directory can be run, respectively, to setup both prometheus and also our anka-prometheus-exporter. 
### [`run-prometheus-on-docker.bash`](./PROMETHEUS/run-prometheus-on-docker.bash)

- Running this script will create a docker container pre-configured and ready for the anka-prometheus-exporter. It is setup to run on http://anka.prometheus:8095.
- If the first argument is `--uninstall`, it will only remove the existing containers

### [`install-and-run-anka-prometheus-on-mac.bash`](./PROMETHEUS/install-and-run-anka-prometheus-on-mac.bash)

- Running this script will start a background process for the exporter which is connected and pulling from the Anka Build Cloud, which is also running locally.
- If the first argument is `--uninstall`, it will only kill the running exporter

> The process will not persist through restarts. You can just re-run the script to start it again.

---
