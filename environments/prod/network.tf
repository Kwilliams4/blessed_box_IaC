resource "aws_vpc" "prod_vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name        = "prod-vpc"
    Environment = "prod"
  }
}

resource "aws_internet_gateway" "prod_igw" {
  vpc_id = aws_vpc.prod_vpc.id

  tags = {
    Name        = "prod-igw"
    Environment = "prod"
  }
}

resource "aws_subnet" "prod_public_a" {
  vpc_id                  = aws_vpc.prod_vpc.id
  cidr_block              = local.public_a_cidr
  availability_zone       = local.availability_zones[0]
  map_public_ip_on_launch = true

  tags = {
    Name        = "prod-public-a"
    Environment = "prod"
  }
}

resource "aws_subnet" "prod_public_b" {
  vpc_id                  = aws_vpc.prod_vpc.id
  cidr_block              = local.public_b_cidr
  availability_zone       = local.availability_zones[1]
  map_public_ip_on_launch = true

  tags = {
    Name        = "prod-public-b"
    Environment = "prod"
  }
}

resource "aws_subnet" "prod_private_a" {
  vpc_id            = aws_vpc.prod_vpc.id
  cidr_block        = local.private_a_cidr
  availability_zone = local.availability_zones[0]

  tags = {
    Name        = "prod-private-a"
    Environment = "prod"
  }
}

resource "aws_subnet" "prod_private_b" {
  vpc_id            = aws_vpc.prod_vpc.id
  cidr_block        = local.private_b_cidr
  availability_zone = local.availability_zones[1]

  tags = {
    Name        = "prod-private-b"
    Environment = "prod"
  }
}

resource "aws_route_table" "prod_public" {
  vpc_id = aws_vpc.prod_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.prod_igw.id
  }

  tags = {
    Name        = "prod-public"
    Environment = "prod"
  }
}

resource "aws_route_table_association" "prod_public_a" {
  subnet_id      = aws_subnet.prod_public_a.id
  route_table_id = aws_route_table.prod_public.id
}

resource "aws_route_table_association" "prod_public_b" {
  subnet_id      = aws_subnet.prod_public_b.id
  route_table_id = aws_route_table.prod_public.id
}

resource "aws_eip" "prod_nat_a" {
  domain = "vpc"

  tags = {
    Name        = "prod-nat-a-eip"
    Environment = "prod"
  }
}

resource "aws_eip" "prod_nat_b" {
  domain = "vpc"

  tags = {
    Name        = "prod-nat-b-eip"
    Environment = "prod"
  }
}

resource "aws_nat_gateway" "prod_nat_a" {
  allocation_id = aws_eip.prod_nat_a.id
  subnet_id     = aws_subnet.prod_public_a.id

  tags = {
    Name        = "prod-nat-a"
    Environment = "prod"
  }

  depends_on = [aws_internet_gateway.prod_igw]
}

resource "aws_nat_gateway" "prod_nat_b" {
  allocation_id = aws_eip.prod_nat_b.id
  subnet_id     = aws_subnet.prod_public_b.id

  tags = {
    Name        = "prod-nat-b"
    Environment = "prod"
  }

  depends_on = [aws_internet_gateway.prod_igw]
}

resource "aws_route_table" "prod_private_a" {
  vpc_id = aws_vpc.prod_vpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.prod_nat_a.id
  }

  tags = {
    Name        = "prod-private-a"
    Environment = "prod"
  }
}

resource "aws_route_table" "prod_private_b" {
  vpc_id = aws_vpc.prod_vpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.prod_nat_b.id
  }

  tags = {
    Name        = "prod-private-b"
    Environment = "prod"
  }
}

resource "aws_route_table_association" "prod_private_a" {
  subnet_id      = aws_subnet.prod_private_a.id
  route_table_id = aws_route_table.prod_private_a.id
}

resource "aws_route_table_association" "prod_private_b" {
  subnet_id      = aws_subnet.prod_private_b.id
  route_table_id = aws_route_table.prod_private_b.id
}
