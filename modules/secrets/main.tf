# ________________________ Auth SVC ___________________________
# 1. Create a fixed-name container for the JWT Secret
resource "aws_secretsmanager_secret" "jwt_secret" {
  name                    = "gym/dev/auth-service/jwt"
  description             = "JWT Token Signing Secret for gym-auth-service"
  recovery_window_in_days = 0 # Forces immediate deletion if destroyed
}

# 2. Generate a highly secure random string for the JWT token signature
resource "random_password" "jwt_signing_key" {
  length  = 64
  special = true
}

# 3. Store the generated string as plain text inside the secret wrapper
resource "aws_secretsmanager_secret_version" "jwt_secret_val" {
  secret_id     = aws_secretsmanager_secret.jwt_secret.id
  secret_string = random_password.jwt_signing_key.result
}

# A. Generate a secure random string for the Database Master Password
resource "random_password" "db_password" {
  length  = 24
  special = false # Avoids complex symbols that occasionally cause SQL connection string parsing issues
}

# B. Create a fixed-name container for the DB Credentials
resource "aws_secretsmanager_secret" "db_secret" {
  name                    = "gym/dev/auth-rds-credentials" 
  description             = "Master user database credentials for auth-postgres"
  recovery_window_in_days = 0 
}

# C. Store the generated credentials as a JSON object inside the wrapper
resource "aws_secretsmanager_secret_version" "db_secret_val" {
  secret_id     = aws_secretsmanager_secret.db_secret.id
  secret_string = jsonencode({
    username = "auth_admin"
    password = random_password.db_password.result
  })
}