1, "18, 'Invalid cross-device link'" IO 错误
    这个错误是 centos7 的 3.10 内核和 kernel-lt 内核 overlayfs 实现的限制，对 rename(2) 的支持有问题，kernel-ml 内核（5.0内核以上）已解决。
