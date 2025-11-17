import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import { dirname } from 'path';
import yaml from 'js-yaml';
import { createAPIMonitoringDashboard } from './dashboards/api-monitoring.js';
import { createNewsMonitoringDashboard } from './dashboards/news-monitoring.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

async function generateDashboards() {
  console.log('Generating dashboards...');

  // Generate API monitoring dashboard
  const apiDashboard = createAPIMonitoringDashboard();

  // Generate News monitoring dashboard
  const newsDashboard = createNewsMonitoringDashboard();

  // Create output directory
  const outputDir = path.join(__dirname, '..', 'output');
  const k8sDir = path.join(__dirname, '..', '..', 'k8s', 'grafana', 'dashboards');

  if (!fs.existsSync(outputDir)) {
    fs.mkdirSync(outputDir, { recursive: true });
  }

  if (!fs.existsSync(k8sDir)) {
    fs.mkdirSync(k8sDir, { recursive: true });
  }

  // Write dashboard JSON to output directory
  const jsonPath = path.join(outputDir, 'api-monitoring.json');
  fs.writeFileSync(jsonPath, JSON.stringify(apiDashboard, null, 2));
  console.log(`✓ Generated: ${jsonPath}`);

  // Create Kubernetes ConfigMap for API dashboard
  const configMap = {
    apiVersion: 'v1',
    kind: 'ConfigMap',
    metadata: {
      name: 'gd-api-monitoring',
      namespace: 'o11y',
      labels: {
        grafana_dashboard: '1',
        app: 'grafana'
      }
    },
    data: {
      'api-monitoring.json': JSON.stringify(apiDashboard)
    }
  };

  // Write ConfigMap YAML
  const yamlPath = path.join(k8sDir, 'api-monitoring.yaml');
  const yamlContent = yaml.dump(configMap, {
    indent: 2,
    lineWidth: -1,
    noRefs: true
  });

  fs.writeFileSync(yamlPath, yamlContent);
  console.log(`✓ Generated: ${yamlPath}`);

  // Write news dashboard JSON to output directory
  const newsJsonPath = path.join(outputDir, 'news-monitoring.json');
  fs.writeFileSync(newsJsonPath, JSON.stringify(newsDashboard, null, 2));
  console.log(`✓ Generated: ${newsJsonPath}`);

  // Create Kubernetes ConfigMap for news dashboard
  const newsConfigMap = {
    apiVersion: 'v1',
    kind: 'ConfigMap',
    metadata: {
      name: 'gd-news-monitoring',
      namespace: 'o11y',
      labels: {
        grafana_dashboard: '1',
        app: 'grafana'
      }
    },
    data: {
      'news-monitoring.json': JSON.stringify(newsDashboard)
    }
  };

  // Write ConfigMap YAML for news dashboard
  const newsYamlPath = path.join(k8sDir, 'news-monitoring.yaml');
  const newsYamlContent = yaml.dump(newsConfigMap, {
    indent: 2,
    lineWidth: -1,
    noRefs: true
  });

  fs.writeFileSync(newsYamlPath, newsYamlContent);
  console.log(`✓ Generated: ${newsYamlPath}`);

  console.log('\nDone! Deploy with:');
  console.log('  kubectl apply -f k8s/grafana/dashboards/api-monitoring.yaml');
  console.log('  kubectl apply -f k8s/grafana/dashboards/news-monitoring.yaml');
}

// Run generation
generateDashboards().catch(error => {
  console.error('Error generating dashboards:', error);
  process.exit(1);
});
