set.seed(123)
count = 0
n = 2000
list = numeric(n)
for(i in 1:n){
  x = runif(n=1)
  y = runif(n=1)
  # print(x^2+y^2)
  if((x^2+y^2)<1){
    count = count + 1
  }
  list[i] <- count/i  
}

print(list[n]*4)