FROM nvcr.io/nvidia/tensorrt:21.08-py3

ENV DEBIAN_FRONTEND=nonintercative

RUN mkdir -p /ees_app_

WORKDIR /ees_app_

# clone git repos
RUN apt-get -y update && apt-get install -y git && \
     git clone https://github.com/imshamsher/opencv_src.git && \
	   git clone https://github.com/imshamsher/ffmpeg_src.git

# Install dependent packages
RUN apt-get -y update && apt-get install -y wget nano build-essential yasm \
                           pkg-config xmlstarlet unzip curl \
                          libsm6 libxext6 libxrender-dev vim language-pack-en

# Install specific cmake version i.e 3.13.5
RUN apt-get update
RUN apt remove --purge --auto-remove cmake
RUN wget https://github.com/Kitware/CMake/releases/download/v3.13.5/cmake-3.13.5.tar.gz
RUN tar xvf cmake-3.13.5.tar.gz && cd cmake-3.13.5 && ./configure && make -j$(nproc) && make install && \
       ln -s /usr/local/bin/cmake /usr/bin/cmake 

# Install TensorRT OSS version 8.0.1
RUN cd /ees_app_/ && git clone -b 21.08 https://github.com/nvidia/TensorRT && \
	cd TensorRT/ && git submodule update --init --recursive && export TRT_SOURCE=`pwd` && \
	cd $TRT_SOURCE && mkdir -p build && cd build && \
	/usr/local/bin/cmake .. -DGPU_ARCHS="86 80 75 61 62 70"  -DTRT_LIB_DIR=/usr/lib/x86_64-linux-gnu/ -DCMAKE_C_COMPILER=/usr/bin/gcc \
	-DTRT_BIN_DIR=`pwd`/out && make nvinfer_plugin -j$(nproc) && \ 
	mv /usr/lib/x86_64-linux-gnu/libnvinfer_plugin.so.8.0.1 ${HOME}/libnvinfer_plugin.so.8.0.1.bak && \
	cp libnvinfer_plugin.so.8.0.1  /usr/lib/x86_64-linux-gnu/libnvinfer_plugin.so.8.0.1

RUN apt-get install libssl-dev -y
RUN export TRT_LIB_PATH=”/usr/lib/x86_64-linux-gnu”
RUN export TRT_INC_PATH=”/usr/include/x86_64-linux-gnu”
RUN apt-get update


# Install EES source code

COPY src /ees_app_/src

# Install opencv for darknet
RUN mkdir /ees_app_/opencv_src/opencv/build

RUN cd /ees_app_/opencv_src/opencv/build/ && \
     cmake -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr/local \
          -DOPENCV_GENERATE_PKGCONFIG=ON ..  && \
     make -j8 && \
      make install -j8

# Install darknet
RUN git clone https://github.com/imshamsher/darknet.git

RUN cd /ees_app_/darknet && \
     make -j8

RUN apt-get install ffmpeg -y

# Link the libcuda stub to the location where tensorflow is searching for it and reconfigure
# dynamic linker run-time bindings
RUN ln -s /usr/local/cuda/lib64/stubs/libcuda.so /usr/local/cuda/lib64/stubs/libcuda.so.1 \
    && echo "/usr/local/cuda/lib64/stubs" > /etc/ld.so.conf.d/z-cuda-stubs.conf \
    && ldconfig

ENV NVIDIA_DRIVER_CAPABILITIES video,compute,utility

ENV QT_X11_NO_MITSHM=1

COPY src /ees_app_/src/

RUN cp /ees_app_/darknet/libdarknet.so /ees_app_/src/

RUN apt-get -y install gstreamer1.0-tools
RUN apt-get -y install gstreamer1.0-plugins-base
RUN apt-get -y install gstreamer1.0-plugins-good
RUN apt-get -y install gstreamer1.0-plugins-bad
RUN apt-get -y install gstreamer1.0-plugins-ugly
RUN apt-get -y install gstreamer1.0-libav

# Check if installation is okay
RUN which gst-launch-1.0

#############################
# Python Gstreamer bindings #
#############################

RUN apt-get -y install python3-gst-1.0

COPY requirements.txt /ees_app_/requirements.txt

RUN pip3 install -r /ees_app_/requirements.txt

COPY trt_requirements.txt /ees_app_/trt_requirements.txt

RUN pip3 install -r /ees_app_/trt_requirements.txt
