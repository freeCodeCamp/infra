import { describe, test, expect, beforeAll } from 'vitest';
import { createAPIMonitoringDashboard } from '../src/dashboards/api-monitoring.js';

interface Dashboard {
  uid: string;
  title: string;
  tags: string[];
  panels: Panel[];
  templating: {
    list: Variable[];
  };
  refresh: string;
  time: {
    from: string;
    to: string;
  };
}

interface Panel {
  type: string;
  title: string;
  gridPos: {
    x: number;
    y: number;
    w: number;
    h: number;
  };
  targets?: Target[];
}

interface Target {
  expr: string;
}

interface Variable {
  name: string;
  type: string;
}

describe('API Monitoring Dashboard', () => {
  let dashboard: Dashboard;

  beforeAll(() => {
    dashboard = createAPIMonitoringDashboard();
  });

  test('should have correct UID', () => {
    expect(dashboard.uid).toBe('freecodecamp-api-v1');
  });

  test('should have correct title', () => {
    expect(dashboard.title).toBe('freeCodeCamp API Dashboard');
  });

  test('should have required tags', () => {
    expect(dashboard.tags).toContain('Node.js');
    expect(dashboard.tags).toContain('API');
    expect(dashboard.tags).toContain('Loki');
  });

  test('should have exactly 12 panels', () => {
    expect(dashboard.panels).toHaveLength(12);
  });

  test('should have LOKI_DATASOURCE variable', () => {
    const lokiVar = dashboard.templating.list.find(v => v.name === 'LOKI_DATASOURCE');
    expect(lokiVar).toBeDefined();
    expect(lokiVar?.type).toBe('datasource');
  });

  test('should have stack variable', () => {
    const stackVar = dashboard.templating.list.find(v => v.name === 'stack');
    expect(stackVar).toBeDefined();
    expect(stackVar?.type).toBe('query');
  });

  test('all panels should have valid LogQL queries', () => {
    dashboard.panels.forEach(panel => {
      if (panel.targets && panel.targets.length > 0) {
        panel.targets.forEach(target => {
          // Check that query expression exists and contains basic LogQL structure
          expect(target.expr).toBeDefined();
          expect(typeof target.expr).toBe('string');
          expect(target.expr.length).toBeGreaterThan(0);

          // Verify queries contain service and swarm_stack labels
          if (!panel.title.includes('Raw')) {
            expect(target.expr).toMatch(/service="api"/);
            expect(target.expr).toMatch(/swarm_stack="\$stack"/);
          }
        });
      }
    });
  });

  test('should not have overlapping panels', () => {
    const positions = dashboard.panels.map(panel => ({
      x: panel.gridPos.x,
      y: panel.gridPos.y,
      w: panel.gridPos.w,
      h: panel.gridPos.h
    }));

    // Check for overlaps (simplified check - assumes 24-column grid)
    for (let i = 0; i < positions.length; i++) {
      for (let j = i + 1; j < positions.length; j++) {
        const p1 = positions[i];
        const p2 = positions[j];

        // Panels overlap if they share the same Y position and X ranges intersect
        if (p1.y === p2.y) {
          const xOverlap = p1.x < p2.x + p2.w && p2.x < p1.x + p1.w;
          expect(xOverlap).toBe(false);
        }
      }
    }
  });

  test('Request Rate panel should exist', () => {
    const requestRatePanel = dashboard.panels.find(p => p.title === 'Request Rate (RPS)');
    expect(requestRatePanel).toBeDefined();
    expect(requestRatePanel?.gridPos.w).toBe(4);
  });

  test('all queries should handle errors gracefully', () => {
    dashboard.panels.forEach(panel => {
      if (panel.targets && panel.targets.length > 0) {
        panel.targets.forEach(target => {
          // Verify queries include error handling (except logs panels)
          if (panel.type !== 'logs') {
            expect(target.expr).toContain('__error__=""');
          }
        });
      }
    });
  });

  test('timeseries panels should use $__interval', () => {
    const timeSeriesPanels = dashboard.panels.filter(p => p.type === 'timeseries');

    timeSeriesPanels.forEach(panel => {
      panel.targets?.forEach(target => {
        expect(target.expr).toContain('$__interval');
      });
    });
  });

  test('stat panels should use $__range for accurate totals', () => {
    const statPanels = dashboard.panels.filter(p => p.type === 'stat');

    statPanels.forEach(panel => {
      panel.targets?.forEach(target => {
        expect(target.expr).toContain('$__range');
      });
    });
  });

  test('dashboard should have 5m refresh interval', () => {
    expect(dashboard.refresh).toBe('5m');
  });

  test('dashboard should have time range from now-1h to now', () => {
    expect(dashboard.time.from).toBe('now-1h');
    expect(dashboard.time.to).toBe('now');
  });

  test('status code count panels should show 0 instead of no data', () => {
    const statusPanels = ['2xx', '4xx', '5xx'];

    statusPanels.forEach(title => {
      const panel = dashboard.panels.find(p => p.title === title);
      expect(panel).toBeDefined();
      expect(panel?.targets?.[0].expr).toContain('or vector(0)');
    });
  });

  describe('Row 1 Layout', () => {
    test('should have 7 stat panels in Row 1', () => {
      const row1Panels = dashboard.panels.filter(p => p.gridPos.y === 0);
      expect(row1Panels).toHaveLength(7);
      row1Panels.forEach(panel => {
        expect(panel.type).toBe('stat');
      });
    });

    test('Row 1 panels should be in correct order', () => {
      const row1Panels = dashboard.panels
        .filter(p => p.gridPos.y === 0)
        .sort((a, b) => a.gridPos.x - b.gridPos.x);

      const expectedOrder = [
        'Total Requests',
        'Request Rate (RPS)',
        '2xx',
        '4xx',
        '5xx',
        'P95',
        'P99'
      ];

      expectedOrder.forEach((title, index) => {
        expect(row1Panels[index].title).toBe(title);
      });
    });

    test('Row 1 panels should use full 24-column width', () => {
      const row1Panels = dashboard.panels.filter(p => p.gridPos.y === 0);
      const totalWidth = row1Panels.reduce((sum, panel) => sum + panel.gridPos.w, 0);
      expect(totalWidth).toBe(24);
    });
  });

  describe('Row 2 Layout', () => {
    test('should have 2 timeseries panels in Row 2', () => {
      const row2Panels = dashboard.panels.filter(p => p.gridPos.y === 4);
      expect(row2Panels).toHaveLength(2);
      row2Panels.forEach(panel => {
        expect(panel.type).toBe('timeseries');
      });
    });

    test('Row 2 panels should be equal width', () => {
      const row2Panels = dashboard.panels.filter(p => p.gridPos.y === 4);
      expect(row2Panels[0].gridPos.w).toBe(12);
      expect(row2Panels[1].gridPos.w).toBe(12);
    });

    test('Requests by Status should be on left, Latency Percentiles on right', () => {
      const row2Panels = dashboard.panels
        .filter(p => p.gridPos.y === 4)
        .sort((a, b) => a.gridPos.x - b.gridPos.x);

      expect(row2Panels[0].title).toBe('Requests by Status');
      expect(row2Panels[0].gridPos.x).toBe(0);
      expect(row2Panels[1].title).toBe('Latency Percentiles');
      expect(row2Panels[1].gridPos.x).toBe(12);
    });
  });

  describe('Top 10 Tables', () => {
    test('should have 2 Top 10 table panels', () => {
      const topKPanels = dashboard.panels.filter(p => p.title.startsWith('Top 10'));
      expect(topKPanels).toHaveLength(2);
      topKPanels.forEach(panel => {
        expect(panel.type).toBe('table');
      });
    });

    test('Top 10 queries should strip query parameters from URLs', () => {
      const topKPanels = dashboard.panels.filter(p => p.title.startsWith('Top 10'));

      topKPanels.forEach(panel => {
        panel.targets?.forEach(target => {
          expect(target.expr).toContain('regexReplaceAll');
          expect(target.expr).toContain('clean_path');
        });
      });
    });
  });

  describe('Query Patterns', () => {
    test('latency queries should convert microseconds to milliseconds', () => {
      const latencyPanels = ['P95', 'P99', 'Latency Percentiles', 'Top 10 Slowest Endpoints (P95)'];

      latencyPanels.forEach(title => {
        const panel = dashboard.panels.find(p => p.title === title);
        if (panel && panel.targets) {
          panel.targets.forEach(target => {
            expect(target.expr).toContain('/ 1000');
          });
        }
      });
    });

    test('latency percentile panels should use aggregation to prevent series limit', () => {
      const latencyPanels = ['P95', 'P99', 'Latency Percentiles'];

      latencyPanels.forEach(title => {
        const panel = dashboard.panels.find(p => p.title === title);
        if (panel && panel.targets) {
          panel.targets.forEach(target => {
            // These panels should aggregate to single series to avoid 500 series limit
            expect(target.expr).toContain('avg by()');
            expect(target.expr).toContain('quantile_over_time');
          });
        }
      });
    });

    test('status code queries should use correct ranges', () => {
      const panel2xx = dashboard.panels.find(p => p.title === '2xx');
      const panel4xx = dashboard.panels.find(p => p.title === '4xx');
      const panel5xx = dashboard.panels.find(p => p.title === '5xx');

      expect(panel2xx?.targets?.[0].expr).toContain('>= 200');
      expect(panel2xx?.targets?.[0].expr).toContain('< 300');

      expect(panel4xx?.targets?.[0].expr).toContain('>= 400');
      expect(panel4xx?.targets?.[0].expr).toContain('< 500');

      expect(panel5xx?.targets?.[0].expr).toContain('>= 500');
      expect(panel5xx?.targets?.[0].expr).toContain('< 600');
    });
  });

  describe('Panel Grid Validation', () => {
    test('all panels should have valid grid positions', () => {
      dashboard.panels.forEach(panel => {
        expect(panel.gridPos.x).toBeGreaterThanOrEqual(0);
        expect(panel.gridPos.x).toBeLessThan(24);
        expect(panel.gridPos.y).toBeGreaterThanOrEqual(0);
        expect(panel.gridPos.w).toBeGreaterThan(0);
        expect(panel.gridPos.w).toBeLessThanOrEqual(24);
        expect(panel.gridPos.h).toBeGreaterThan(0);
      });
    });

    test('no panel should exceed 24-column grid width', () => {
      dashboard.panels.forEach(panel => {
        expect(panel.gridPos.x + panel.gridPos.w).toBeLessThanOrEqual(24);
      });
    });

    test('panels should be ordered by Y then X position', () => {
      for (let i = 0; i < dashboard.panels.length - 1; i++) {
        const current = dashboard.panels[i];
        const next = dashboard.panels[i + 1];

        if (current.gridPos.y === next.gridPos.y) {
          expect(current.gridPos.x).toBeLessThanOrEqual(next.gridPos.x);
        }
      }
    });
  });

  describe('Logs Panel', () => {
    test('should have logs panel at bottom', () => {
      const logsPanel = dashboard.panels.find(p => p.title === 'Logs');
      expect(logsPanel).toBeDefined();
      expect(logsPanel?.type).toBe('logs');

      // Should be at highest Y position
      const maxY = Math.max(...dashboard.panels.map(p => p.gridPos.y));
      expect(logsPanel?.gridPos.y).toBe(maxY);
    });

    test('logs panel should span full width', () => {
      const logsPanel = dashboard.panels.find(p => p.title === 'Logs');
      expect(logsPanel?.gridPos.w).toBe(24);
    });

    test('logs query should not filter by error', () => {
      const logsPanel = dashboard.panels.find(p => p.title === 'Logs');
      const target = logsPanel?.targets?.[0];
      expect(target?.expr).not.toContain('__error__=""');
    });
  });
});
