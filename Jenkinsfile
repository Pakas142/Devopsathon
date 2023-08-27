pipeline {
    agent any
 stages {
     stage('Pull Code') {
         steps {
          // Pull code from GitHub repository
            git 'https://github.com/Pakas142/Devopsathon.git'
        }
      }
      stage('build docker image') {
         steps {
          // Pull code from GitHub repository
            sh 'sudo docker build -t pakas142:latest .'
            sh 'sudo docker images'
        }
      }
      stage('Build the Docker image') {
            steps {
                sh 'sudo docker build -t pakas142/devopsathon:latest .'
                sh 'sudo docker tag pakas142/devopsathon:latest pakas142/devopsathon:${BUILD_NUMBER}'
            }
        }
      stage('Push the Docker image') {
            steps {
                sh 'sudo docker image push pakas142/devopsathon:latest'
                sh 'sudo docker image push pakas142/devopsathon:${BUILD_NUMBER}'
            }
        }
      stage('Terraform Apply') {
            steps {
                sh 'terraform init'
                sh 'terraform plan'
                sh '/usr/bin/terraform apply --auto-approve'
            }
        }
    }                                

}
