set.seed(123)
count <- 0
n <- 200000
estimativas_pi <- numeric(n)

for (i in 1:n) {
  x <- runif(1)
  y <- runif(1)
  
  if ((x^2 + y^2) < 1) {
    count <- count + 1
  }
  
  # Multiplica por 4 para estimar pi em vez de pi/4
  estimativas_pi[i] <- (4*count / i)
}

# Exibe a estimativa final no console
print(estimativas_pi[n])

# Plota a convergência para pi
plot(estimativas_pi, type = "l", ylab = "Estimativa de Pi", xlab = "Iterações")
abline(h = pi, col = "red", lty = 2, lwd = 1.5)