# Getting Started with KubeBuddy Radar API

This guide will help you make your first API call to KubeBuddy Radar. Whether you're a developer building integrations or someone exploring the API for the first time, this guide has you covered.

## What you'll learn

- How to get your API credentials
- Making your first API request
- Understanding responses
- Common errors and how to fix them
- Best practices for using the API

## Quick summary

- **Base URL:** `https://radar.kubebuddy.io/api/kb-radar/v1`
- **Authentication:** All endpoints require authentication (browser session or API key)
- **Format:** JSON responses with consistent structure
- **Pro feature:** Cluster run history endpoints are available for Pro users

## Step 1: Get your API key

Before you can use the API, you need to create an API key:

1. **Log in** to your KubeBuddy Radar account
2. Go to **Account** → **Developer API Access**
3. Click **Create a key** and give it a name (e.g., "My First Key")
4. **Copy the key immediately** - it's only shown once!
5. Store it securely (like in a password manager)

**Important notes:**
- Keys are WordPress Application Passwords tied to your account
- Your account page only shows keys you've created
- You can create multiple keys (limit depends on your plan)
- You can revoke keys anytime if they're compromised

**What you'll need for authentication:**
- Your WordPress **username** (not email)
- Your generated **application password**

## Step 2: Make your first request

Let's fetch a list of cloud-native projects. We'll show examples in different tools so you can pick what works best for you.

### Using curl (Command Line)

Curl is available on Mac, Linux, and Windows (Git Bash or PowerShell). Replace `username` and `app_password` with your credentials:

```bash
curl -u "username:app_password" \
  "https://radar.kubebuddy.io/api/kb-radar/v1/projects?per_page=3"
```

### Using PowerShell (Windows)

```powershell
$user = "your_username"
$pass = "your_app_password"
$token = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("${user}:${pass}"))
$headers = @{ Authorization = "Basic $token" }

Invoke-RestMethod "https://radar.kubebuddy.io/api/kb-radar/v1/projects?per_page=3" -Headers $headers
```

### Using Python

```python
import requests
from requests.auth import HTTPBasicAuth

auth = HTTPBasicAuth("your_username", "your_app_password")

response = requests.get(
    "https://radar.kubebuddy.io/api/kb-radar/v1/projects?per_page=3",
    auth=auth
)

data = response.json()
print(f"Found {data['total']} projects total")
print(f"Showing page {data['page']} of {data['total_pages']}")

for project in data['items']:
    print(f"- {project['name']} ({project['category']})")
```

## Step 2b: Upload your first cluster run (Pro)

Cluster run upload accepts KubeBuddy JSON reports only.

```bash
curl -u "username:app_password" \
  -H "Content-Type: application/json" \
  -X POST "https://radar.kubebuddy.io/api/kb-radar/v1/cluster-reports" \
  -d '{
    "environment": "prod",
    "cluster": { "name": "bluegreen-test-uks" },
    "report": {
      "metadata": {
        "clusterName": "bluegreen-test-uks",
        "score": 79.0,
        "kubernetesVersion": "v1.34.2"
      },
      "checks": {}
    }
  }'
```

Then query:

- `GET /cluster-reports`
- `GET /cluster-reports/compare`
- `GET /cluster-reports/trends`
- `GET /cluster-reports/{run_id}/freshness`
- `GET /cluster-configs`
- `GET /cluster-configs/{config_id}/command`
- `GET /cluster-configs/{config_id}/config-file`

See [Cluster Reports (Pro)](cluster-reports.md) and [Cluster Configs (Pro)](cluster-configs.md) for full details.

### Using JavaScript/Node.js

```javascript
const fetch = require('node-fetch');

const username = 'your_username';
const password = 'your_app_password';
const auth = Buffer.from(`${username}:${password}`).toString('base64');

fetch('https://radar.kubebuddy.io/api/kb-radar/v1/projects?per_page=3', {
  headers: {
    'Authorization': `Basic ${auth}`
  }
})
  .then(res => res.json())
  .then(data => {
    console.log(`Found ${data.total} projects total`);
    data.items.forEach(project => {
      console.log(`- ${project.name} (${project.category})`);
    });
  });
```

## Step 3: Understanding the response

When you make a request, you'll get a JSON response. Here's what a typical response looks like:

```json
{
  "page": 1,
  "per_page": 3,
  "total": 256,
  "total_pages": 86,
  "items": [
    {
      "id": 12,
      "name": "Argo CD",
      "description": "Declarative GitOps CD for Kubernetes",
      "category": "CI/CD",
      "cncf_status": "graduated",
      "homepage": "https://argo-cd.readthedocs.io",
      "repo_url": "https://github.com/argoproj/argo-cd",
      "logo_url": "https://radar.kubebuddy.io/logos/argo-cd.png",
      "latest_version": "v2.10.4",
      "latest_published_at": "2024-06-02 10:35:20"
    }
  ]
}
```

**Understanding the fields:**
- **Pagination fields** (`page`, `per_page`, `total`, `total_pages`): Help you navigate through large result sets
- **items array**: Contains the actual data you requested
- **Project fields**: Include everything from basic info to latest release details

**Note:** To check which projects you're subscribed to, use the separate `GET /my-subscriptions` endpoint. This separation enables aggressive CDN caching for the main catalog.

## Step 4: Try more endpoints

Now that you've made your first request, try these common use cases:

### Search for specific projects

```bash
# Search by name or keyword
curl -u "username:app_password" \
  "https://radar.kubebuddy.io/api/kb-radar/v1/projects?search=kubernetes&per_page=5"
```

### Filter by CNCF status

```bash
# Get only graduated (production-ready) projects
curl -u "username:app_password" \
  "https://radar.kubebuddy.io/api/kb-radar/v1/projects?cncf_status=graduated&per_page=10"
```

### Get recent releases

```bash
# Get the 10 most recent releases across all projects
curl -u "username:app_password" \
  "https://radar.kubebuddy.io/api/kb-radar/v1/recent-releases?limit=10"
```

### Find security updates

```bash
# Get only releases with security fixes
curl -u "username:app_password" \
  "https://radar.kubebuddy.io/api/kb-radar/v1/recent-releases?limit=10&security_only=1"
```

### Get your tracked projects

```bash
# See what projects you're subscribed to
curl -u "username:app_password" \
  "https://radar.kubebuddy.io/api/kb-radar/v1/subscriptions"
```

### Get platform statistics

```bash
# See how many projects and releases are tracked
curl -u "username:app_password" \
  "https://radar.kubebuddy.io/api/kb-radar/v1/stats"
```

## Step 5: Common errors and solutions

When working with the API, you might encounter these errors. Here's how to fix them:

### 401 Unauthorized

**What it means:** Your credentials are missing or incorrect.

**How to fix:**
1. Make sure you're using your WordPress **username**, not your email
2. Double-check your application password (copy it exactly, including spaces)
3. Verify the Authorization header is formatted correctly
4. Test with a simple curl command first to verify credentials work

**Example error:**
```json
{
  "code": "rest_forbidden",
  "message": "Authentication required."
}
```

### 403 Forbidden

**What it means:** You're authenticated, but don't have permission for this resource.

**How to fix:**
1. Check if the endpoint requires a Pro or Pro Plus plan
2. Verify you haven't exceeded your subscription limit
3. Make sure you're accessing your own resources (can't access other users' data)

**Example error:**
```json
{
  "code": "rest_forbidden",
  "message": "API access requires a Pro plan."
}
```

### 404 Not Found

**What it means:** The endpoint or resource doesn't exist.

**How to fix:**
1. Verify the base URL: `https://radar.kubebuddy.io/api/kb-radar/v1`
2. Check the endpoint path in the [API Reference](api-reference.md)
3. Make sure resource IDs exist (e.g., valid project ID)
4. Verify you're using the correct HTTP method (GET, POST, DELETE, etc.)

### Quick diagnostic test

Test if your credentials work:

```bash
# This should return your dashboard data if auth is working
curl -v -u "your_username:your_app_password" \
  "https://radar.kubebuddy.io/api/kb-radar/v1/dashboard"
```

If you see `< HTTP/2 200` in the output, your authentication is working!

## Step 6: Best practices

### Security tips
- **Never commit API keys** to version control (use `.gitignore`)
- **Use environment variables** to store credentials
- **Create separate keys** for different environments (dev, staging, production)
- **Rotate keys regularly** (every 90 days recommended)
- **Revoke unused keys** immediately

**Example using environment variables:**

```bash
# Set environment variables (Linux/Mac)
export KUBEBUDDY_USERNAME="your_username"
export KUBEBUDDY_PASSWORD="your_app_password"

# Use in curl
curl -u "$KUBEBUDDY_USERNAME:$KUBEBUDDY_PASSWORD" \
  "https://radar.kubebuddy.io/api/kb-radar/v1/projects"
```

```powershell
# Set environment variables (PowerShell)
$env:KUBEBUDDY_USERNAME = "your_username"
$env:KUBEBUDDY_PASSWORD = "your_app_password"

# Use in request
$user = $env:KUBEBUDDY_USERNAME
$pass = $env:KUBEBUDDY_PASSWORD
$token = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("${user}:${pass}"))
```

### Performance tips
- **Cache responses** client-side (5-10 minute TTL is reasonable)
- **Use pagination** efficiently - don't fetch all 200+ projects at once
- **Filter server-side** rather than fetching everything and filtering locally
- **Batch operations** when possible

**Example caching in Python:**

```python
import requests
from requests.auth import HTTPBasicAuth
import time

class KubeBuddyClient:
    def __init__(self, username, password):
        self.auth = HTTPBasicAuth(username, password)
        self.base_url = "https://radar.kubebuddy.io/api/kb-radar/v1"
        self.cache = {}
        self.cache_duration = 300  # 5 minutes
    
    def get_projects(self, page=1, per_page=20):
        cache_key = f"projects_{page}_{per_page}"
        now = time.time()
        
        # Check cache
        if cache_key in self.cache:
            cached_time, data = self.cache[cache_key]
            if now - cached_time < self.cache_duration:
                return data
        
        # Fetch from API
        response = requests.get(
            f"{self.base_url}/projects",
            auth=self.auth,
            params={"page": page, "per_page": per_page}
        )
        data = response.json()
        
        # Store in cache
        self.cache[cache_key] = (now, data)
        return data

# Usage
client = KubeBuddyClient("username", "password")
projects = client.get_projects(page=1, per_page=20)
```

### Error handling tips
- **Implement retry logic** with exponential backoff
- **Handle rate limits gracefully** (wait 60 seconds)
- **Log errors with context** for debugging
- **Validate responses** before processing
- **Provide user-friendly error messages**

**Example retry logic in Python:**

```python
import requests
import time

def api_request_with_retry(url, auth, max_retries=3):
    for attempt in range(max_retries):
        try:
            response = requests.get(url, auth=auth)
            response.raise_for_status()
            return response.json()
            
        except requests.exceptions.RequestException as e:
            if attempt == max_retries - 1:
                raise
            
            # Exponential backoff
            wait_time = (2 ** attempt)
            print(f"Request failed. Retrying in {wait_time} seconds...")
            time.sleep(wait_time)
    
    raise Exception("Max retries exceeded")
```

## Next steps

### Build something cool
Now that you understand the basics, here are some ideas:

1. **Release monitor:** Track your critical projects and get notified of new releases
2. **Security dashboard:** Monitor security fixes across your stack
3. **Changelog aggregator:** Build a single changelog for all your dependencies
4. **CI/CD integration:** Auto-update dependencies when new versions are released
5. **Slack/Teams bot:** Post release notifications to your team channels

### Explore the full API
- Read the complete [API Reference](api-reference.md)
- Learn about [subscription management](api-reference.md#subscription-management)
- Explore [label organization](api-reference.md#label-management)
- Set up [webhooks for notifications](api-reference.md#post-update-settings)

### Use the MCP Server
If you're using AI coding assistants like Claude, Windsurf, or Cursor:
- Check out the main KubeBuddy docs for MCP guidance when that page is published in the unified docs set
- Integrate KubeBuddy directly into your AI workflow

### Join the community
- Share your integrations and use cases
- Get help from other developers
- Request new features

## Need help?

If you're stuck or have questions:

- **Documentation:** [KubeBuddy Radar Docs](index.md)
- **API Reference:** [Complete endpoint documentation](api-reference.md)
- **Support:** Contact us through the website

When asking for help, include:
- What you're trying to do
- The API endpoint you're using
- Your code (remove credentials!)
- The full error message
- Expected vs. actual behavior

Happy coding! 🚀
