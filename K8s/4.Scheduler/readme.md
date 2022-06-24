Kubernetes scheduler架构和调度流程
![image](https://github.com/Lincoln-dac/kube-linux/blob/master/pic/20220513102806.png)

Kubernetes的调度策略与算法

主要有两类算法：Predicate和Priority。Predicate是对于所有的node进行筛选，滤除不合格的节点，Priority是对于Predicate筛选过的node进行打分，挑选最优的节点。通过Predicate策略筛选符合条件的Node，主要是node上不同的pod会存在资源冲突，Predicate主要的目的是为了避免资源冲突、节点超载、端口的冲突等。

![image](https://github.com/Lincoln-dac/kube-linux/blob/master/pic/20220513102816.png)
![image](https://github.com/Lincoln-dac/kube-linux/blob/master/pic/20220513102825.png)

https://mp.weixin.qq.com/s/e6jh61iqIJPAMyjwSehL5g
