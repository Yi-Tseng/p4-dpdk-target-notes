# P4 DPDK target notes

## Build P4 code

There is a very simple L1 switch based on PSA architecture in this repo (see `l1switch`)

Before building the p4 code, please install [p4lang/p4c](https://github.com/p4lang/p4c)

To build the P4 code:

```bash
cd l1switch
./build.sh
```

After compiled, you will get:

- main.spec: the pipeline config
- main.bfrt.json: the bfrt/tdi config
- main.pb.txt: P4Runtime config
- context.json: pipeline context file

## Build P4 DPDK switch

System tested: Ubuntu 20.04

To build p4 dpdk target, follow the README from [p4-dpdk-target](https://github.com/p4lang/p4-dpdk-target)
Github repository.

Copy-and-paste steps:

```bash
# Set up some environment variables that we need them later
# Assume you want to install everything under your home directory
export SDE=$HOME/sde
export SDE_INSTALL=$SDE/install
export LD_LIBRARY_PATH=$SDE_INSTALL/lib:$SDE_INSTALL/lib64:$SDE_INSTALL/lib/x86_64-linux-gnu/:/usr/local/lib64:/usr/local/lib

# Some dependencies to build the SDE/p4-dpdk-target
sudo apt update && \
sudo apt install -y git automake cmake python3 python3-pip
pip3 install distro # Required by `p4-dpdk-target/tools/setup/sysutils.py` to detect the OS

# Download everything we need
mkdir -p $SDE_INSTALL
cd $SDE
RUN git clone --depth=1 https://github.com/p4lang/target-utils --recursive utils
RUN git clone --depth=1 https://github.com/p4lang/target-syslibs --recursive syslibs
RUN git clone --depth=1 https://github.com/p4lang/p4-dpdk-target --recursive p4-dpdk-target

# Some other dependencies, here are packets installed (with apt-get command):
# git unifdef curl python3-setuptools python3-pip python3-wheel python3-cffi
# libconfig-dev libunwind-dev libffi-dev zlib1g-dev libedit-dev libexpat1-dev clang
# ninja-build gcc libstdc++6 autotools-dev autoconf autoconf-archive libtool meson
# google-perftools connect-proxy tshark
# ... and installed with pip3:
# thrift protobuf pyelftools scapy six

sudo -E python3 p4-dpdk-target/tools/setup/install_dep.py
cd $SDE/utils && \
    mkdir build && \
    cd build && \
    cmake -DCMAKE_INSTALL_PREFIX=$SDE_INSTALL -DCPYTHON=1 -DSTANDALONE=ON .. && \
    make -j && \
    make install
cd $SDE/syslibs && \
    mkdir build && \
    cd build && \
    cmake -DCMAKE_INSTALL_PREFIX=$SDE_INSTALL .. && \
    make -j && \
    make install
cd $SDE/p4-dpdk-target && \
    git submodule update --init --recursive --force && \
    ./autogen.sh && \
    ./configure --prefix=$SDE_INSTALL && \
    make -j && \
    make install

# refresh path so we will use python3 from SDE instead the default one
ln -s $SDE_INSTALL/bin/python3.8 $SDE_INSTALL/bin/python3
```

## Run P4 DPDK target

### Prepare port config

We need to tell the switch how to connect to ports, here is the json schema for port config:

```jsonc
{
    "ports": [
        {
            "dev_port": 0, // The port ID
            "port_name": "", // The port name, will create a tap port with this name if "port_type" is "tap"
            "mempool_name": "", // The DPDK memory pool name, default will be "MEMPOOL0"
            "pipe_name": "", // The pipeline for this port, will be "p4_pipeline_name" in the switch config in next section.
            "port_dir": "", // "default", "in", or "out"
            "port_in_id": 0, // required when port_dir is "default" or "in"
            "port_out_id": 0, // required when port_dir is "default" or "out"
            "port_type": "", // "tap", "link", "source", or "sink"
            // required when port type is "tap"
            "tap_port_attributes": {
                "mtu": 1500
            },
            // required when port type is "link"
            "link_port_attributes": {
                "pcie_bdf": "", // BDF: bus, devece, function
                "dev_args": "",
                "dev_hotplug_enabled": 0
            },
            // required when port type is "source"
            "source_port_attributes": {
                "file_name": ""
            },
            // required when port type is "sink"
            "sink_port_attributes": {
                "file_name": ""
            }
        }
    ]
}
```

Here is an example for L1 switch which contains only two ports with id 0 and 1:

```json
{
    "ports": [
        {
            "dev_port": 0,
            "port_name": "veth0",
            "mempool_name": "MEMPOOL0",
            "pipe_name": "pipe",
            "port_dir": "default",
            "port_in_id": 0,
            "port_out_id": 0,
            "port_type": "tap",
            "tap_port_attributes": {
                "mtu": 1500
            }
        },
        {
            "dev_port": 1,
            "port_name": "veth1",
            "mempool_name": "MEMPOOL0",
            "pipe_name": "pipe",
            "port_dir": "default",
            "port_in_id": 1,
            "port_out_id": 1,
            "port_type": "tap",
            "tap_port_attributes": {
                "mtu": 1500
            }
        }

    ]
}
```

### Prepare switch config

You also need to create a switch config file to tell the switch where to load the pipeline
and port config, here we provide a simple switch config:

```json
{
    "chip_list": [
        {
            "id": "asic-0",
            "chip_family": "dpdk",
            "instance": 0
        }
    ],
    "instance": 0,
    "p4_devices": [
        {
            "device-id": 0,
            "eal-args": "dummy -n 4 -c 7",
            "p4_programs": [
                {
                    "program-name": "l1switch",
                    "sai_default_init": false,
                    "bfrt-config": "Absolute path to main.bfrt.json",
                    "port-config": "Absolute path to ports.json",
                    "p4_pipelines": [
                        {
                            "p4_pipeline_name": "pipe",
                            "context": "Absolute path to context.json",
                            "config": "Absolute path to main.spec",
                            "pipe_scope": [
                                0
                            ],
                            "path": "Absolute path to where you pit pipeline configs"
                        }
                    ]
                }
            ]
        }
    ]
}
```

Modify the path to the correct file and save it(e.g. switch_config.json)

### Start the switch

To start the switch, run the following script:

```bash
# Basic environment variables we need
export SDE=$HOME/sde
export SDE_INSTALL=$SDE/install
export LD_LIBRARY_PATH=$SDE_INSTALL/lib:$SDE_INSTALL/lib64:$SDE_INSTALL/lib/x86_64-linux-gnu/:/usr/local/lib64:/usr/local/lib
# We need to put SDE executable path before the system one since the bfrt_python
# needs to use Python libraries from it and use the Python executable from SDE
export PATH=$SDE_INSTALL/bin:$PATH
hash -r

# For security reason, the PATH and LD_LIBRARY_PATH won't pass to root user even if we use "sudo -E"
# We must pass them in sudo to make sure it is correct.
sudo -E PATH=$PATH LD_LIBRARY_PATH=$LD_LIBRARY_PATH $SDE_INSTALL/bin/bf_switchd --install-dir $SDE_INSTALL --conf switch_config.json
```

### Enable the pipeline

After started the switch, you need to enable the pipeline first before processing any
packets:

```text
bfshell> bfrt_python
In [1]: bfrt
------> bfrt()
Available symbols:
dump                 - Command
info                 - Command
l1switch             - Node
port                 - Node


bfrt> l1switch.enable
----> l1switch.enable()
```

### Send some traffic between ports

One way to test the pipeline with `TAP` ports is to use scapy and tcpdump

For example, start a tcpdump to dump packets from `veth1`

```bash
sudo tcpdump -i veth1 -vvv
```

And send few packets to veth0 by using Scapy (with root privileged)

```python
from scapy.all import *
pkt = Ether() / IP() / UDP() / "Hello world"
sendp(pkt, iface='veth0')
```

Another way is to create network namespace and move TAP ports to network namespaces.

```bash
sudo ip netns add h1
sudo ip netns add h2
sudo ip link set netns h1 dev veth0
sudo ip link set netns h2 dev veth1
sudo ip netns exec h1 ip addr add 10.0.0.1/24 dev veth0
sudo ip netns exec h2 ip addr add 10.0.0.2/24 dev veth1
sudo ip netns exec h1 ip link set veth0 up
sudo ip netns exec h2 ip link set veth1 up
ip netns exec h1 ping 10.0.0.2

# Cleanup
ip netns del h1
ip netns del h2
```

## Start the switch in container

We can also start the switch in a container, first is to build the container image:

```bash
docker build -t p4-dpdk .
```

And we can start container:

```bash
docker run -it --rm --privileged -v /dev/hugepages:/dev/hugepages p4-dpdk:latest
```

Note that p4-dpdk-target requries Hugepage setup, so we need to mount hugepage to the container
and set privileged mode (also required for creating TAP port)

You can mount/place your config(.spec/.bfrt.json/context.json/ports.json) to the container and start the switch
as mentioned in previous section.
