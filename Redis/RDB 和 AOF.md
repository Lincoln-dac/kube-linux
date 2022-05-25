Redis持久化⽅案分为RDB和AOF两种。


![image](https://github.com/Lincoln-dac/kube-linux/blob/master/pic/642.png)

RDB

RDB持久化是把当前进程数据生成快照保存到硬盘的过程，触发RDB持久化过程分为手动触发和自动触发。

RDB⽂件是⼀个压缩的⼆进制⽂件，通过它可以还原某个时刻数据库的状态。由于RDB⽂件是保存在硬盘上的，所以即使Redis崩溃或者退出，只要RDB⽂件存在，就可以⽤它来恢复还原数据库的状态。

手动触发分别对应save和bgsave命令:
![image](https://github.com/Lincoln-dac/kube-linux/blob/master/pic/643.png)


save命令：阻塞当前Redis服务器，直到RDB过程完成为止，对于内存比较大的实例会造成长时间阻塞，线上环境不建议使用。

bgsave命令：Redis进程执行fork操作创建子进程，RDB持久化过程由子进程负责，完成后自动结束。阻塞只发生在fork阶段，一般时间很短。


以下场景会自动触发RDB持久化：

使用save相关配置，如“save m n”。表示m秒内数据集存在n次修改时，自动触发bgsave。
如果从节点执行全量复制操作，主节点自动执行bgsave生成RDB文件并发送给从节点
执行debug reload命令重新加载Redis时，也会自动触发save操作
默认情况下执行shutdown命令时，如果没有开启AOF持久化功能则自动执行bgsave。


AOF

AOF（append only file）持久化：以独立日志的方式记录每次写命令， 重启时再重新执行AOF文件中的命令达到恢复数据的目的。AOF的主要作用是解决了数据持久化的实时性，目前已经是Redis持久化的主流方式。

AOF的工作流程操作：命令写入 （append）、文件同步（sync）、文件重写（rewrite）、重启加载 （load）

![image](https://github.com/Lincoln-dac/kube-linux/blob/master/pic/644.png)


流程如下：

1）所有的写入命令会追加到aof_buf（缓冲区）中。

2）AOF缓冲区根据对应的策略向硬盘做同步操作。

3）随着AOF文件越来越大，需要定期对AOF文件进行重写，达到压缩 的目的。

4）当Redis服务器重启时，可以加载AOF文件进行数据恢复。


RDB 和 AOF 各自有什么优缺点？
RDB | 优点

只有一个紧凑的二进制文件 dump.rdb，非常适合备份、全量复制的场景。
容灾性好，可以把RDB文件拷贝道远程机器或者文件系统张，用于容灾恢复。
恢复速度快，RDB恢复数据的速度远远快于AOF的方式
RDB | 缺点

实时性低，RDB 是间隔一段时间进行持久化，没法做到实时持久化/秒级持久化。如果在这一间隔事件发生故障，数据会丢失。
存在兼容问题，Redis演进过程存在多个格式的RDB版本，存在老版本Redis无法兼容新版本RDB的问题。
AOF | 优点

实时性好，aof 持久化可以配置 appendfsync 属性，有 always，每进行一次命令操作就记录到 aof 文件中一次。
通过 append 模式写文件，即使中途服务器宕机，可以通过 redis-check-aof 工具解决数据一致性问题。
AOF | 缺点

AOF 文件比 RDB 文件大，且 恢复速度慢。
数据集大 的时候，比 RDB 启动效率低。
10.RDB和AOF如何选择？
一般来说， 如果想达到足以媲美数据库的 数据安全性，应该 同时使用两种持久化功能。在这种情况下，当 Redis 重启的时候会优先载入 AOF 文件来恢复原始的数据，因为在通常情况下 AOF 文件保存的数据集要比 RDB 文件保存的数据集要完整。
如果 可以接受数分钟以内的数据丢失，那么可以 只使用 RDB 持久化。
有很多用户都只使用 AOF 持久化，但并不推荐这种方式，因为定时生成 RDB 快照（snapshot）非常便于进行数据备份， 并且 RDB 恢复数据集的速度也要比 AOF 恢复的速度要快，除此之外，使用 RDB 还可以避免 AOF 程序的 bug。
如果只需要数据在服务器运行的时候存在，也可以不使用任何持久化方式。
