Set up a full GitOps workflow with ArgoCD in a multi-cluster Minikube environment, dynamic environments per PR, and automated cleanup.

Step 1: Create 4 Minikube Clusters

```
# DevOps Cluster (ArgoCD controller will run here)
minikube start -p devops --memory 4096 --cpus 2

# Test Cluster
minikube start -p test --memory 2048 --cpus 2

# Stage Cluster
minikube start -p stage --memory 2048 --cpus 2

# Prod Cluster
minikube start -p prod --memory 2048 --cpus 2
```
need to added all the clusters to argocd @!@

Step 2: Install ArgoCD in DevOps Cluster
```
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```
Expose ArgoCD API server
`kubectl port-forward svc/argocd-server -n argocd 8080:443`

Get admin password
`kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)`


Login
`argocd login localhost:8080 --username admin --password $(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)`

Step 3: Create Node.js App
```
mkdir gitops-nodejs-app && cd gitops-nodejs-app
npm init -y
npm install express
```

server.js
```
const express = require('express');
const app = express();
const port = process.env.PORT || 3000;

app.get('/', (req, res) => res.send('Hello from PR env!'));
app.listen(port, () => console.log(`App listening on port ${port}`));
```

Step 4: Dockerfile
```
FROM node:18-alpine
WORKDIR /app
COPY gitops-nodejs-app/package*.json ./
RUN npm install
COPY gitops-nodejs-app/server.js .
EXPOSE 3000
CMD ["node", "server.js"]
```

Step 5: Helm Chart
`helm create gitops-nodejs-app-chart`

Modify values.yaml
```
replicaCount: 1
image:
  repository: <dockerhub username>/gitops-nodejs-app
  tag: latest
  pullPolicy: Always

service:
  port: 3000
```
templates/deployment.yaml
```
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ include "nodejs-app-chart.fullname" . }}
  labels:
    app: {{ include "nodejs-app-chart.name" . }}
spec:
  replicas: {{ .Values.replicaCount }}
  selector:
    matchLabels:
      app: {{ include "nodejs-app-chart.name" . }}
  template:
    metadata:
      labels:
        app: {{ include "nodejs-app-chart.name" . }}
    spec:
      containers:
        - name: {{ .Chart.Name }}
          image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
          imagePullPolicy: {{ .Values.image.pullPolicy }}
          ports:
            - containerPort: {{ .Values.service.port }}
```

Step 6: GitHub Repository & CI/CD

Create repo secrets in github for 
`DOCKERHUB_USERNAME` 
`DOCKERHUB_PASSWORD`
`ARGOCD_PASSWORD`
`ARGOCD_USERNAME`
`ARGOCD_SERVER`
`TOKEN`

Create `.github/workflows/pr-deploy.yml`
```
name: PR Review Env

on:
  pull_request:
    types: [opened, synchronize, reopened, closed]

jobs:
  build:
    runs-on: ubuntu-latest
    env:
      DOCKERHUB_USERNAME: ${{ secrets.DOCKERHUB_USERNAME }}
      DOCKERHUB_PASSWORD: ${{ secrets.DOCKERHUB_PASSWORD }}
    steps:
      - name: Checkout
        uses: actions/checkout@v3

      - name: Set PR Namespace and Image Tag
        if: github.event.action != 'closed'
        run: |
          echo "PR_NUMBER=${{ github.event.pull_request.number }}" >> $GITHUB_ENV
          echo "IMAGE_TAG=pr-${{ github.event.pull_request.number }}" >> $GITHUB_ENV

      - name: Build Docker image
        if: github.event.action != 'closed'
        run: |
          docker build -t $DOCKERHUB_USERNAME/gitops-nodejs-app:$IMAGE_TAG .
      
      - name: Docker login
        if: github.event.action != 'closed'
        run: echo $DOCKERHUB_PASSWORD | docker login -u $DOCKERHUB_USERNAME --password-stdin

      - name: Push Docker image
        if: github.event.action != 'closed'
        run: docker push $DOCKERHUB_USERNAME/gitops-nodejs-app:$IMAGE_TAG

      - name: Update Helm Chart Tag
        if: github.event.action != 'closed'
        run: |
          sed -i "s/tag: .*/tag: $IMAGE_TAG/" gitops-nodejs-app-chart/values.yaml

      - name: Add review label
        uses: actions-ecosystem/action-add-labels@v1
        with:
          labels: review
        env:
          GITHUB_TOKEN: ${{ secrets.TOKEN }}
```

Step 7: ArgoCD ApplicationSet with PR generator

applicationset.yaml
```
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: pr-reviews
  namespace: argocd
spec:
  generators:
  - pullRequest:
      repoURL: https://github.com/ITBeyder/gitops-nodejs-app.git
      labels:
        - review
  template:
    metadata:
      name: pr-{{PR_NUMBER}}
    spec:
      project: default
      source:
        repoURL: https://github.com/ITBeyder/gitops-nodejs-app.git
        targetRevision: HEAD
        path: gitops-nodejs-app-chart
        helm:
          valueFiles:
            - values.yaml
      destination:
        server: https://kubernetes.default.svc
        namespace: pr-{{PR_NUMBER}}
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
```

Step 8: Workflow Summary

* PR with review label → GitHub Actions triggers.
* Build Docker image → push to DockerHub.
* Update Helm chart image tag.
* ArgoCD ApplicationSet deploys to Test cluster → dynamic namespace.
* PR merged/closed → ArgoCD deletes the namespace.
