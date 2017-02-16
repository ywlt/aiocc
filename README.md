Automatic I/O congestion control(AIOCC)
=========================
[![TeamCity CodeBetter](https://img.shields.io/teamcity/codebetter/bt428.svg?maxAge=2592000)]()
[![Packagist](https://img.shields.io/packagist/v/symfony/symfony.svg?maxAge=2592000)]()
[![Yii2](https://img.shields.io/badge/Powered_by-multexu Framework-green.svg?style=flat)]()
![Progress](http://progressed.io/bar/80?title=completed )


#[AIOCC主页](http://www.dengshijun.cn/aiocc.jsp)

在HPC存储系统和云存储系统中，为了实现高性能和高并行，一个I/O操作通常被分割为若干个请求序列，同时将这些请求发送到服务器端，导致存储系统中涌现大量资源竞争，如存储带宽。HPC存储系统和云存储系统中，通常会有成百上千个客户端，运行各类应用，每个应用会发送一定数量的I/O请求。因此存储系统中会充斥着大量的请求，资源竞争十分激烈。

传统的方案多为局部优化，如优化数据在磁盘上的分布、网络拥塞控制、路由选择等方案，并不能有效应对分布式文件系统中负载压力较大时，对有限的资源（如带宽、磁盘访问时间片等）的竞争问题。这些竞争会大大降低存储系统效率，例如：争夺网络带宽会导致网络丢包、超时以及非预期的中断连接；在服务端争夺存储器资源会降低缓存效率、增加存储器访问时延，基于闪存的存储系统还可能导致写放大的问题。如果存储系统缺乏对这些竞争的管控，一旦负载压力过大时，整个系统的效率将大大下降，甚至可能崩溃。因此在分布式文件系统中，设计一种I/O拥塞控制机制来协调和控制系统的I/O访问，保证系统高效运行就显得尤为重要。

当前针对分布式文件系统的拥塞管理和资源竞争控制，通常的解决方案是针对某些控制对象，设定一个上限值，这个上限值一般是系统管理员直接控制，或者由系统内节点周期性协商。以Lustre2.8为例，Lustre提供了网络请求调度器（Network Request Scheduler，NRS）用户接口，让用户可以改变控制策略，设置控制参数，以进行控制和管理。这类方案一定程度上能解决的拥塞管理和资源竞争控制的问题，但存在以下方面的局限性：

- 现实性：手动管理无法实时有效应对分布式文件系统中成千上万个节点，以及节点中的各类参数；
- 有效性：无法系统、全面、准确地认知整个存储系统的情况，因此有时调节是无效调控，甚至适得其反；
- 及时性：手动调节需要长时间的性能测试和系统调试，具有滞后性；
- 灵敏度：对负载变化不敏感；
- 高代价：需要专业的人员对系统进行大量的测试，代价高昂；

基于以上分析，对分布式文件系统的I/O行为进行端到端智能化控制和管理，实现针对分布式文件系统的自动I/O行为控制管理方案具有很大实用价值。
本方案提出一种基于机器学习的分布式文件系统可扩展的自动I/O拥塞控制机制，应对存储系统中的资源竞争，提高资源利用率，降低系统性能偏差，实现**性能隔离**（performance isolation），应用**程序/作业/进程的公平性**（applications/jobs/ processes fairness）和**延迟控制**（latency control）。

#AIOCC的特点
- 系统地对分布式文件系统I/O负载特征进行分析处理：研究存储系统 I/O 数据规律，包括I/O 负载特征的经验分布、I/O 到达间隔时间的相关性以及I/O 负载的自相似性等，并对不同时期、不同层级、不同类型的典型I/O 负载，合成短小、精确的特征负载。
- 自动进行对存储特征负载测试，运用数理统计方法对测试结果进行处理，评估规则对特征负载的调控效果；
- 使用机器学习的方式产生/优化规则库，基于规则自动管理存储系统中资源竞争，提高资源利用率；
- 优化自动调节的过程，实施端到端控制；
- 在Lustre文件系统实现上述方案原型；



#AIOCC架构

![image](https://github.com/ShijunDeng/aiocc/blob/master/source/image/architecture_aiocc.png)

**AIOCC说明**

AIOCC说明是在Lustre2.8+CenOS7上实现原型系统,并在[MULTEXU](https://github.com/ShijunDeng/multexu)、[LustreTools](https://github.com/ShijunDeng/LustreTools)、[ASCAR](https://github.com/mlogic/ascar-lustre-sharp)基础上开发的。AIOCC针对的是CentOS7（Linux kernel 3.10.0-327.el7.x86_64）和Lustre2.8.0，其它版本的系统使用本工具可能需要解决一些兼容性问题。另外，CentOS7在安装过程中，选择的版本和安装配置不同，也可能导致一些包的依赖性问题，因此建议CentOS7的安装过程参照视频教程进行安装。AIOCC自带Lustre2.8.0全套安装文件。
## 反馈与建议
- QQ：946057490
- 邮箱：<dengshijun1992@gmail.com> <sjdeng@hust.edu.cn>

---------
感谢您阅读这份帮助文档。