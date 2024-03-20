# Project Deployment Notes

## Getting the initial project running

### Required Technologies

- Node/npm
- Docker
- Terraform
- gcloud
- Make

### Clone the base project

```
git clone https://github.com/sidpalas/storybooks.git
```

### Install npm dependencies

```
npm install

npm audit
```

### Run mongodb database inside docker

```
sudo docker run -p 27017:27017 -d mongo:3.6-xenial
```

### Setup config.env file

```
PORT = 3000
MONGO_URI = mongodb://localhost:27017/storybooks
GOOGLE_CLIENT_ID = <Your client id>
GOOGLE_CLIENT_SECRET = <Your secret key>
```

### Run the project in dev mode

```
npm run dev
```

- Visit: http://localhost:3000


## Applying DevOps Techniques

### Step 1: Dockerize the application

#### Create a .dockerignore file

Add the following contents in .dockerignore file

```
node_modules
terraform
```

#### Create a Dockerfile

Contents of the Dockerfile

```
FROM node:14-slim

WORKDIR /usr/src/app

COPY ./package*.json ./

RUN npm install

COPY . .

USER node

EXPOSE 3000

CMD ["npm", "start"]
```


#### Build the docker image

```
docker build -t storybooks-app .
```

#### Docker Compose

Create a yaml file called docker-compose.yml

```
version: '3'
services:
  api-server:
    build: ./
    entrypoint: [ "npm", "run", "dev" ]
    env_file: ./config/config.env
    ports:
      - '3000:3000'
    networks:
      - storybooks-app
    volumes:
      - ./:/usr/src/app
      - /usr/src/app/node_modules
    depends_on:
      - mongo
  mongo:
    image: mongo:3.6-xenial
    environment:
      - MONGO_INITDB_DATABASE=storybooks
    ports:
      - '27017:27017'
    networks:
      - storybooks-app
    volumes:
      - mongo-data:/data/db

networks:
  storybooks-app:
    driver: bridge

volumes:
  mongo-data:
    driver: local

```

Now, update the MONGO_URI in the config.env file to:

```
MONGO_URI=mongodb://mongo:27017/storybooks

```


##### Run Docker Compose

```
sudo docker-compose up
```


#### Create a Makefile

```
run-local:
	docker-compose up 
```


### Step 2: Terraform

#### Infrastructure as Code

Create main.tf

```
terraform {
  backend "gcs" {
    bucket = "devops-directive-storybooks-terraform"
    prefix = "/state/storybooks"
  }
}
```

Create gcp.tf

```
provider "google" {
  credentials = file("terraform-sa-key.json")
  project     = var.gcp_project_id
  region      = "us-central1"
  zone        = "us-central1-c"
  version     = "~> 3.38"
}
```

#### GCP Resources

Edit gcp.tf

```

# IP ADDRESS
resource "google_compute_address" "ip_address" {
  name = "storybooks-ip-${terraform.workspace}"
}

# NETWORK
data "google_compute_network" "default" {
  name = "default"
}

# FIREWALL RULE
resource "google_compute_firewall" "allow_http" {
  name    = "allow-http-${terraform.workspace}"
  network = data.google_compute_network.default.name

  allow {
    protocol = "tcp"
    ports    = ["80"]
  }

  source_ranges = ["0.0.0.0/0"]

  target_tags = ["allow-http-${terraform.workspace}"]
}

# OS IMAGE
data "google_compute_image" "cos_image" {
  family  = "cos-81-lts"
  project = "cos-cloud"
}

# COMPUTE ENGINE INSTANCE
resource "google_compute_instance" "instance" {
  name         = "${var.app_name}-vm-${terraform.workspace}"
  machine_type = var.gcp_machine_type
  zone         = "us-central1-a"

  tags = google_compute_firewall.allow_http.target_tags

  boot_disk {
    initialize_params {
      image = data.google_compute_image.cos_image.self_link
    }
  }

  network_interface {
    network = data.google_compute_network.default.name

    access_config {
      nat_ip = google_compute_address.ip_address.address
    }
  }

  service_account {
    scopes = ["storage-ro"]
  }
}

```

#### Atlas Mongodb Resources

Create atlas.tf

```
provider "mongodbatlas" {
  public_key  = var.mongodbatlas_public_key
  private_key = var.mongodbatlas_private_key
  version     = "~> 0.6"
}

# cluster
resource "mongodbatlas_cluster" "mongo_cluster" {
  project_id = var.atlas_project_id
  name       = "${var.app_name}-${terraform.workspace}"
  num_shards = 1

  replication_factor           = 3
  provider_backup_enabled      = true
  auto_scaling_disk_gb_enabled = true
  mongo_db_major_version       = "3.6"

  //Provider Settings "block"
  provider_name               = "GCP"
  disk_size_gb                = 10
  provider_instance_size_name = "M10"
  provider_region_name        = "CENTRAL_US"
}

# db user
resource "mongodbatlas_database_user" "mongo_user" {
  username           = "storybooks-user-${terraform.workspace}"
  password           = var.atlas_user_password
  project_id         = var.atlas_project_id
  auth_database_name = "admin"

  roles {
    role_name     = "readWrite"
    database_name = "storybooks"
  }
}

# ip whitelist
resource "mongodbatlas_project_ip_whitelist" "test" {
  project_id = var.atlas_project_id
  ip_address = google_compute_address.ip_address.address
}

```


#### Cloudflare Resources

##### Generate Access Keys

```
Click on Profile on the top right hand corner

Click on Myprofile

Click on API Tokens

Click on Create Token

Set permissions as Zone -> Read

Set permissions as DNS -> Edit

Click on Continue to summary

Copy the generate token

```

Declare a variable in variables.tf file

```
### CLOUDFLARE
variable "cloudflare_api_token" {
  type = string
}

```

Create cloudflare.tf file

```
provider "cloudflare" {
  version   = "~> 2.0"
  api_token = var.cloudflare_api_token
}

# Zone
data "cloudflare_zones" "cf_zones" {
  filter {
    name = var.domain
  }
}

# DNS A record
resource "cloudflare_record" "dns_record" {
  zone_id = data.cloudflare_zones.cf_zones.zones[0].id
  name    = "storybooks${terraform.workspace == "prod" ? "" : "-${terraform.workspace}"}"
  value   = google_compute_address.ip_address.address
  type    = "A"
  proxied = true
}


```


#### Secrets Management

##### Google Secret Manager

Create a secret

```
Click on + CREATE SECRET

Enter a name

Enter the secret value

Click on CREATE SECRET
```


### Step 3: Deployment

Edit Makefile

```
SSH_STRING=palas@storybooks-vm-$(ENV)
OAUTH_CLIENT_ID=542106262510-8ki8hqgu7kmj2b3arjdqvcth3959kmmv.apps.googleusercontent.com

GITHUB_SHA?=latest
LOCAL_TAG=storybooks-app:$(GITHUB_SHA)
REMOTE_TAG=gcr.io/$(PROJECT_ID)/$(LOCAL_TAG)

CONTAINER_NAME=storybooks-api
DB_NAME=storybooks

ssh: check-env
	gcloud compute ssh $(SSH_STRING) \
		--project=$(PROJECT_ID) \
		--zone=$(ZONE)

ssh-cmd: check-env
	@gcloud compute ssh $(SSH_STRING) \
		--project=$(PROJECT_ID) \
		--zone=$(ZONE) \
		--command="$(CMD)"

build:
	docker build -t $(LOCAL_TAG) .

push:
	docker tag $(LOCAL_TAG) $(REMOTE_TAG)
	docker push $(REMOTE_TAG)

deploy: check-env
	$(MAKE) ssh-cmd CMD='docker-credential-gcr configure-docker'
	@echo "pulling new container image..."
	$(MAKE) ssh-cmd CMD='docker pull $(REMOTE_TAG)'
	@echo "removing old container..."
	-$(MAKE) ssh-cmd CMD='docker container stop $(CONTAINER_NAME)'
	-$(MAKE) ssh-cmd CMD='docker container rm $(CONTAINER_NAME)'
	@echo "starting new container..."
	@$(MAKE) ssh-cmd CMD='\
		docker run -d --name=$(CONTAINER_NAME) \
			--restart=unless-stopped \
			-p 80:3000 \
			-e PORT=3000 \
			-e \"MONGO_URI=mongodb+srv://storybooks-user-$(ENV):$(call get-secret,atlas_user_password_$(ENV))@storybooks-$(ENV).kkwmy.mongodb.net/$(DB_NAME)?retryWrites=true&w=majority\" \
			-e GOOGLE_CLIENT_ID=$(OAUTH_CLIENT_ID) \
			-e GOOGLE_CLIENT_SECRET=$(call get-secret,google_oauth_client_secret) \
			$(REMOTE_TAG) \
			'
```

#### Build the new version of docker image

```
make build
```

#### Push to google container registry

```
make push
```

#### Deploy

```
make deploy
```


### Step 4: CI/CD

#### Github Actions

Add @ sign before the statements in make file

```
deploy: check-env
	$(MAKE) ssh-cmd CMD='docker-credential-gcr configure-docker'
	@echo "pulling new container image..."
	$(MAKE) ssh-cmd CMD='docker pull $(REMOTE_TAG)'
	@echo "removing old container..."
	-$(MAKE) ssh-cmd CMD='docker container stop $(CONTAINER_NAME)'
	-$(MAKE) ssh-cmd CMD='docker container rm $(CONTAINER_NAME)'
	@echo "starting new container..."
	@$(MAKE) ssh-cmd CMD='\
		docker run -d --name=$(CONTAINER_NAME) \
			--restart=unless-stopped \
			-p 80:3000 \
			-e PORT=3000 \
			-e \"MONGO_URI=mongodb+srv://storybooks-user-$(ENV):$(call get-secret,atlas_user_password_$(ENV))@storybooks-$(ENV).kkwmy.mongodb.net/$(DB_NAME)?retryWrites=true&w=majority\" \
			-e GOOGLE_CLIENT_ID=$(OAUTH_CLIENT_ID) \
			-e GOOGLE_CLIENT_SECRET=$(call get-secret,google_oauth_client_secret) \
			$(REMOTE_TAG) \
```

Run

```
make deploy
```

##### Github Workflow

Create a .bithub/workflows folder

Create a yaml file inside

```
name: Build and Deploy to Google Compute Engine

on:
  push:
    # Turning off staging for now...
    # branches:
    #   - master
    tags:
      - v\d+\.\d+\.\d+

env:
  PROJECT_ID: devops-directive-storybooks

jobs:
  setup-build-publish-deploy:
    name: Setup, Build, Publish, and Deploy
    runs-on: ubuntu-latest

    steps:
      - name: Set ENV
        run: |-
          if [ ${GITHUB_REF##*/} = "master" ]; then
            echo "ENV=staging" >> $GITHUB_ENV
          else 
            echo "ENV=prod" >> $GITHUB_ENV
          fi

      - name: Checkout
        uses: actions/checkout@v2

      # Setup gcloud CLI
      - uses: GoogleCloudPlatform/github-actions/setup-gcloud@master
        with:
          version: '290.0.1'
          service_account_key: ${{ secrets.GCE_SA_KEY }}
          project_id: ${{ env.PROJECT_ID }}

      # Configure Docker to use the gcloud command-line tool as a credential
      # helper for authentication
      - run: |-
          gcloud --quiet auth configure-docker

      # Build the Docker image
      - name: Build
        run: |-
          make build

      # Push the Docker image to Google Container Registry
      - name: Publish
        run: |-
          make push

      - name: Deploy
        run: |-
          make deploy

```

Commit

Push

```
git push
```


### Step 5: Separate Staging and Production

Create a prod directory inside environments 

Create config.tfvars

```
gcp_machine_type = "n1-standard-4"
```