import sys
cidr_size=int(sys.argv[1])
pool_size=int(sys.argv[2])

if cidr_size < pool_size: 
    message="Error validating pool size: Configured Pool size is bigger than IPs CIDRs can provide. (desiredWorkerPoolSize={0}, availableIPs={1}).".format(pool_size,cidr_size)
    print(message)
    exit(1)
else:
    print('{"message" : "OK"}')
    exit(0)