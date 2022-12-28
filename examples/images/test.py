import argparse

# 初始化参数构造器
parser = argparse.ArgumentParser()

# 在参数构造器中添加两个命令行参数
parser.add_argument('--filename', type=str, default='Siri1')
parser.add_argument('--message', type=str, default=',Welcom to Python World!')

# 获取所有的命令行参数
args = parser.parse_args()

print('Hi ' + str(args.filename) + str(args.message))
