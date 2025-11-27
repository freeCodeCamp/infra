/**
 * LogQL Query Validator
 *
 * Validates LogQL query syntax and catches common errors before deployment.
 */

import type { SimplePanel } from '../builders/simple.js';

export interface ValidationResult {
  valid: boolean;
  errors: ValidationError[];
  warnings: ValidationWarning[];
}

export interface ValidationError {
  query: string;
  message: string;
  fix?: string;
}

export interface ValidationWarning {
  query: string;
  message: string;
  suggestion?: string;
}

/**
 * Validate LogQL query syntax
 */
export function validateLogQLSyntax(query: string): ValidationResult {
  const errors: ValidationError[] = [];
  const warnings: ValidationWarning[] = [];

  // Rule 1: Must have label selector
  if (!query.includes('{')) {
    errors.push({
      query,
      message: 'LogQL queries must start with a label selector',
      fix: 'Add label selector: {label="value"}'
    });
  }

  // Rule 2: Balanced braces
  const openBraces = (query.match(/{/g) || []).length;
  const closeBraces = (query.match(/}/g) || []).length;
  if (openBraces !== closeBraces) {
    errors.push({
      query,
      message: `Unbalanced braces: ${openBraces} opening, ${closeBraces} closing`,
      fix: 'Ensure all { have matching }'
    });
  }

  // Rule 3: Range aggregations need time variables
  if (query.match(/_over_time\([^)]+\)/) && !query.includes('[$')) {
    errors.push({
      query,
      message: 'Range aggregations require time variable',
      fix: 'Add [$__range] or [$__interval] to your aggregation'
    });
  }

  // Rule 4: No line_format in metric queries (CRITICAL)
  if (query.includes('_over_time') && query.includes('line_format')) {
    errors.push({
      query,
      message: 'Cannot use line_format in metric aggregations',
      fix: 'Remove | line_format - it only works for log display, not metrics'
    });
  }

  // Rule 5: Named capture groups in regexp
  if (query.includes('regexp') && !query.includes('?P<')) {
    warnings.push({
      query,
      message: 'regexp should use named capture groups',
      suggestion: 'Use ?P<name>pattern to extract labels'
    });
  }

  // Rule 6: by() labels should be extracted
  const byMatch = query.match(/by\s*\(([^)]+)\)/);
  if (byMatch) {
    const labels = byMatch[1].split(',').map(l => l.trim());
    labels.forEach(label => {
      if (!query.includes(`?P<${label}>`)) {
        errors.push({
          query,
          message: `Label "${label}" used in by() but not extracted`,
          fix: `Add regexp \`...-(?P<${label}>\\w+)\` or json parser to extract the label`
        });
      }
    });
  }

  // Rule 7: Avoid unbounded queries
  const labelSelectorOnly = query.match(/^\{[^}]+\}$/);
  if (labelSelectorOnly && !query.includes('|=') && !query.includes('|~')) {
    warnings.push({
      query,
      message: 'Query has no filters - may return large result sets',
      suggestion: 'Add line filter: |= "pattern" to reduce data volume'
    });
  }

  // Rule 8: Check for common typos
  if (query.includes('count_overtime')) {
    errors.push({
      query,
      message: 'Typo: count_overtime should be count_over_time',
      fix: 'Replace count_overtime with count_over_time'
    });
  }

  return {
    valid: errors.length === 0,
    errors,
    warnings
  };
}

/**
 * Validate entire panel
 */
export async function validatePanel(panel: SimplePanel): Promise<ValidationResult> {
  const errors: ValidationError[] = [];
  const warnings: ValidationWarning[] = [];

  // Structural validation
  if (!panel.title) {
    errors.push({ query: '', message: 'Panel must have a title' });
  }

  if (panel.queries.length === 0) {
    errors.push({ query: '', message: 'Panel must have at least one query' });
  }

  // Validate each query
  for (const query of panel.queries) {
    const result = validateLogQLSyntax(query.loki);
    errors.push(...result.errors);
    warnings.push(...result.warnings);
  }

  return {
    valid: errors.length === 0,
    errors,
    warnings
  };
}

/**
 * Validate all queries in a list of panels
 */
export async function validatePanels(panels: SimplePanel[]): Promise<ValidationResult> {
  const errors: ValidationError[] = [];
  const warnings: ValidationWarning[] = [];

  for (const panel of panels) {
    const result = await validatePanel(panel);
    errors.push(...result.errors);
    warnings.push(...result.warnings);
  }

  return {
    valid: errors.length === 0,
    errors,
    warnings
  };
}

/**
 * Format validation results for console output
 */
export function formatValidationResults(result: ValidationResult): string {
  let output = '';

  if (result.errors.length > 0) {
    output += '\n❌ Errors:\n';
    result.errors.forEach((error, i) => {
      output += `\n${i + 1}. ${error.message}\n`;
      output += `   Query: ${error.query.substring(0, 80)}${error.query.length > 80 ? '...' : ''}\n`;
      if (error.fix) {
        output += `   Fix: ${error.fix}\n`;
      }
    });
  }

  if (result.warnings.length > 0) {
    output += '\n⚠️  Warnings:\n';
    result.warnings.forEach((warning, i) => {
      output += `\n${i + 1}. ${warning.message}\n`;
      output += `   Query: ${warning.query.substring(0, 80)}${warning.query.length > 80 ? '...' : ''}\n`;
      if (warning.suggestion) {
        output += `   Suggestion: ${warning.suggestion}\n`;
      }
    });
  }

  if (result.valid && result.warnings.length === 0) {
    output += '\n✅ All queries valid\n';
  }

  return output;
}
