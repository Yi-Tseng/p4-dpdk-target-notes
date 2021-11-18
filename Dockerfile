FROM ubuntu:20.04

ENV DEBIAN_FRONTEND=noninteractive
ENV SDE=/sde
ENV SDE_INSTALL=$SDE/install
ENV LD_LIBRARY_PATH=$SDE_INSTALL/lib:$SDE_INSTALL/lib64:$SDE_INSTALL/lib/x86_64-linux-gnu/:/usr/local/lib64:/usr/local/lib
ENV PATH=$SDE_INSTALL/bin:$PATH
RUN apt update; apt upgrade -y
RUN apt install -y git curl wget automake cmake clang python3 python3-pip sudo
RUN mkdir -p $SDE_INSTALL

WORKDIR $SDE
RUN git clone --depth=1 https://github.com/p4lang/target-utils --recursive utils
RUN git clone --depth=1 https://github.com/p4lang/target-syslibs --recursive syslibs
RUN git clone --depth=1 https://github.com/p4lang/p4-dpdk-target --recursive p4-dpdk-target
RUN pip3 install distro
RUN cd p4-dpdk-target/tools/setup; python3 install_dep.py
RUN cd $SDE/utils && \
    mkdir build && \
    cd build && \
    cmake -DCMAKE_INSTALL_PREFIX=$SDE_INSTALL -DCPYTHON=1 -DSTANDALONE=ON .. && \
    make -j && \
    make install
RUN cd $SDE/syslibs && \
    mkdir build && \
    cd build && \
    cmake -DCMAKE_INSTALL_PREFIX=$SDE_INSTALL .. && \
    make -j && \
    make install
RUN cd $SDE/p4-dpdk-target && \
    git submodule update --init --recursive --force && \
    ./autogen.sh && \
    ./configure --prefix=$SDE_INSTALL && \
    make -j && \
    make install
# refresh path so we will use python3 from SDE instead the default one
RUN ln -s $SDE_INSTALL/bin/python3.8 $SDE_INSTALL/bin/python3 && hash -r
