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
