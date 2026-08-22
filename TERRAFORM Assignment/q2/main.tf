provider "aws" {
  region = "ap-southeast-2"
}


# Create S3 bucket
resource "aws_s3_bucket" "website" {
  bucket = "1003-first-bucket-20260730"

  tags = {
    Name        = "My bucket"
    Environment = "Dev"
  }
}


# Allow public access
resource "aws_s3_bucket_public_access_block" "website_public_block" {
  bucket = aws_s3_bucket.website.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}


# Enable static website hosting
resource "aws_s3_bucket_website_configuration" "website_config" {
  bucket = aws_s3_bucket.website.id

  index_document {
    suffix = "index.html"
  }

  error_document {
    key = "error.html"
  }
}


# Bucket policy for public read access
resource "aws_s3_bucket_policy" "public_read_policy" {
  bucket = aws_s3_bucket.website.id

  depends_on = [
    aws_s3_bucket_public_access_block.website_public_block
  ]

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Sid       = "PublicReadGetObject"
        Effect    = "Allow"
        Principal = "*"

        Action = [
          "s3:GetObject"
        ]

        Resource = [
          "${aws_s3_bucket.website.arn}/*"
        ]
      }
    ]
  })
}


# Upload index.html
resource "aws_s3_object" "index" {
  bucket = aws_s3_bucket.website.id
  key    = "index.html"

  content = <<EOF
<!DOCTYPE html>
<html>
<head>
    <title>Terraform S3 Website</title>
</head>

<body>
    <h1>Hello from Terraform</h1>
    <p>This website is hosted using Amazon S3.</p>
</body>

</html>
EOF

  content_type = "text/html"
}


# Upload error page
resource "aws_s3_object" "error" {
  bucket = aws_s3_bucket.website.id
  key    = "error.html"

  content = <<EOF
<!DOCTYPE html>
<html>
<body>
<h1>Error - Page Not Found</h1>
</body>
</html>
EOF

  content_type = "text/html"
}


# Output website URL
output "website_url" {
  value = aws_s3_bucket_website_configuration.website_config.website_endpoint
}
