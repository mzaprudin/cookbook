mkdir -p ~/.ssh
# echo key >> ~/.ssh/authorized_keys
echo ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDzA0CbphqnehNf862GwoIyqCGF6zKmgSytQCVm8X7AhjZLMsYiBG8xZmuiytFC7f8yycJrn5pilYKvNVk12yfIOpLTHWrEPrl7kJWx9bgPV5yVYGjJAXv2Fa/6+SSh/uEJPg+k6miXAIwcakAcwdKUy++ohMJvAFjQPJbiA+oyVOeK8ThlBK7YNp233DLreJkwuSL474zrlqdij4fsDT92rQUyrBS9tHilMaNqpTYGZUbrgqpBbj8Nj6eV7V8NmaIhzvzBBQVZd15agdrb8XYI+DI8B5MSOlzMrNe2K5h/VC64LiD489xBLJI1J1HFE/SH5AILOZX84MquN6jAl9RljkAKYZnCocmT39P3dWCxS1KnX4J0KwecIW1OQ/6bdpwym2UCRSD/JuGspqJiBHjyyiEb7267sh1y1zYR/2FYNbfRwq2QLPRXp1ZdAojETrQQvIExmjoesUaJo0CRX4i0gc499QdPcnhstZ1EfhGneurJNxCGcERlyAHmo+3rZzk= m@zBook >> ~/.ssh/authorized_keys
chmod -R go= ~/.ssh
sudo systemctl restart ssh