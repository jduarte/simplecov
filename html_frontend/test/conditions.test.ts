import { beforeAll, describe, expect, test } from 'bun:test';
import { installPageSkeleton, coverageData } from './fixture';
import { activeCoverageType, coverageStat, normalizeCoverageType, primaryCoverageStat } from '../src/coverage';
import { fileId, precomputeFileIds } from '../src/format';
import { materializeSourceFile, renderPage } from '../src/page';
import { renderCoverageSummary } from '../src/render_cells';
import { renderFileList } from '../src/render_list';
import { renderSourceFile } from '../src/render_source';
import { updateTotalsRow } from '../src/totals';
import type { CoverageData, CoverageStat, FileCoverage } from '../src/types';

const FILE = 'lib/conditions.rb';

beforeAll(async () => {
  await precomputeFileIds([FILE]);
});

const stat = (covered: number, total: number): CoverageStat =>
  ({ covered, missed: total - covered, total, percent: total ? (covered * 100) / total : 100, strength: 1 });

// Line 1: a `&&` whose right operand never ran. Line 2: a `||` that took both
// arms. Line 3: a `||=` whose cached path is ignored. Line 4: an `if` that
// missed a branch and a `&&` that missed an arm.
const data: FileCoverage = {
  source: ['a && b', 'c || d', '@x ||= e', 'f if g && h'],
  lines: [1, 1, 1, 1],
  covered_lines: 4,
  total_lines: 4,
  branches: [{ type: 'then', start_line: 4, end_line: 4, coverage: 0, inline: true, report_line: 4 }],
  covered_branches: 0,
  total_branches: 1,
  conditions: [
    { operator: '&&', type: 'evaluated', start_line: 1, end_line: 1, coverage: 0, report_line: 1 },
    { operator: '&&', type: 'short_circuited', start_line: 1, end_line: 1, coverage: 2, report_line: 1 },
    { operator: '||', type: 'evaluated', start_line: 2, end_line: 2, coverage: 1, report_line: 2 },
    { operator: '||', type: 'short_circuited', start_line: 2, end_line: 2, coverage: 1, report_line: 2 },
    { operator: '||=', type: 'evaluated', start_line: 3, end_line: 3, coverage: 1, report_line: 3 },
    { operator: '||=', type: 'short_circuited', start_line: 3, end_line: 3, coverage: 'ignored', report_line: 3 },
    { operator: '&&', type: 'evaluated', start_line: 4, end_line: 4, coverage: 0, report_line: 4 }
  ],
  conditions_covered_percent: 66.66,
  covered_conditions: 4,
  total_conditions: 6
};

function render(file: FileCoverage, conditions = true, branches = true): HTMLElement {
  const el = document.createElement('div');
  el.innerHTML = renderSourceFile(FILE, file, true, branches, false, undefined, undefined, conditions);
  return el.firstElementChild as HTMLElement;
}

const badges = (li: Element): string[] =>
  Array.from(li.querySelectorAll('.hits--condition')).map((badge) => badge.getAttribute('data-content')!);

describe('the source view with condition coverage', () => {
  test('marks a line with a missed arm, after a missed branch on the same line', () => {
    expect(Array.from(render(data).querySelectorAll('ol li')).map((li) => li.className))
      .toEqual(['missed-condition', 'covered', 'covered', 'missed-branch']);
  });

  test('marks it even where branches are not measured', () => {
    expect(render(data, true, false).querySelectorAll('ol li')[3].className).toBe('missed-condition');
  });

  test('labels each arm with its operator and its hits, leaving ignored arms out', () => {
    const lis = render(data).querySelectorAll('ol li');
    expect([badges(lis[0]), badges(lis[2])]).toEqual([['&& evaluated: 0', '&& short-circuited: 2'], ['||= evaluated: 1']]);
  });

  test('escapes the operator in the badge markup and says what the arm was hit', () => {
    const html = renderSourceFile(FILE, data, true, true, false, undefined, undefined, true);
    expect(html).toContain('data-content="&amp;&amp; evaluated: 0" title="&amp;&amp; evaluated hit 0 times"');
  });

  test('summarizes the arms in the header, from the payload percentage', () => {
    expect(render(data).querySelector('.t-condition-summary')!.textContent!.replace(/\s+/g, ' ').trim())
      .toBe('Condition coverage: 66.66% 4/6 condition arms covered, 2 missed');
  });

  test('counts nothing for a file whose payload carries no condition figures', () => {
    const bare: FileCoverage = { source: ['a'], lines: [1], covered_lines: 1, total_lines: 1 };
    expect(render(bare).querySelector('.t-condition-summary')!.textContent).toContain('100.00% 0/0 condition arms covered');
  });

  test('colours the missed arms in the summary', () => {
    expect(render(data).querySelector('.t-condition-summary .missed-condition-text')!.textContent).toBe('2 missed');
  });

  test('measures no conditions unless asked to', () => {
    const el = document.createElement('div');
    el.innerHTML = renderSourceFile(FILE, data, true, true, false);
    expect([el.querySelector('.t-condition-summary'), el.querySelectorAll('.hits--condition').length]).toEqual([null, 0]);
  });

  test('shows no condition statuses, badges, or summary where the run did not measure them', () => {
    const el = render(data, false);
    expect([el.querySelectorAll('.hits--condition').length, el.querySelector('.t-condition-summary')])
      .toEqual([0, null]);
    expect(el.querySelectorAll('ol li')[0].className).toBe('covered');
  });
});

describe('the summary', () => {
  test('counts conditions it was handed no figures for as none', () => {
    const html = renderCoverageSummary({
      coveredLines: 0, totalLines: 0, coveredBranches: 0, totalBranches: 0, coveredMethods: 0, totalMethods: 0,
      lineCoverage: true, branchCoverage: false, methodCoverage: false, conditionCoverage: true, showMethodToggle: false
    });
    expect(html).toContain('0/0 condition arms covered');
  });

  test('adds nothing after the method summary where conditions are not measured', () => {
    const html = renderCoverageSummary({
      coveredLines: 0, totalLines: 0, coveredBranches: 0, totalBranches: 0, coveredMethods: 0, totalMethods: 0,
      lineCoverage: true, branchCoverage: false, methodCoverage: false, showMethodToggle: false
    });
    expect(html).toEndWith('disabled</span>\n  </div></div>');
  });
});

describe('the file list with condition coverage', () => {
  function list(conditionCoverage: boolean, coverage: FileCoverage = data): HTMLElement {
    const el = document.createElement('div');
    el.innerHTML = renderFileList({
      containerId: 'g-total', title: 'All Files', filenames: [FILE],
      stats: { lines: stat(4, 4), conditions: stat(4, 6) },
      allCoverage: { [FILE]: coverage },
      lineCoverage: true, branchCoverage: false, methodCoverage: false, conditionCoverage,
      primaryCoverage: 'line'
    });
    return el;
  }

  test('adds a column for the arms', () => {
    expect(list(true).querySelector('th[data-sort-key="condition-percent"] .th-label')!.textContent).toBe('Condition Coverage');
  });

  test('heads the column with its covered and total arms', () => {
    const el = list(true);
    expect(['condition-covered', 'condition-total'].map((key) => el.querySelector(`th[data-sort-key="${key}"]`)!.textContent))
      .toEqual(['Covered', 'Arms']);
  });

  test('shows each file its covered and total arms', () => {
    const row = list(true).querySelector('tr.t-file')!;
    const cells = Array.from(row.querySelectorAll('td')).slice(-2).map((cell) => cell.textContent);
    expect(cells).toEqual(['4/', '6']);
  });

  test('totals them in the header row', () => {
    expect(list(true).querySelector('.t-totals__condition-den')!.textContent).toBe('6');
  });

  test('gives each file its figures and the attributes filtering sums', () => {
    const row = list(true).querySelector('tr.t-file') as HTMLElement;
    expect([row.dataset.coveredConditions, row.dataset.totalConditions, row.querySelector('.cell--condition-pct')!.getAttribute('data-order')])
      .toEqual(['4', '6', '66.66']);
  });

  test('reads a file with no condition figures as fully covered and empty', () => {
    const row = list(true, { source: ['a'], lines: [1], covered_lines: 1, total_lines: 1 }).querySelector('tr.t-file') as HTMLElement;
    expect([row.dataset.coveredConditions, row.dataset.totalConditions, row.querySelector('.cell--condition-pct')!.getAttribute('data-order')])
      .toEqual(['0', '0', '100.00']);
  });

  test('leaves the column out where the run did not measure conditions', () => {
    const el = list(false);
    expect([el.querySelector('.t-totals__condition-pct'), el.querySelector('.cell--condition-pct'), (el.querySelector('tr.t-file') as HTMLElement).dataset.totalConditions])
      .toEqual([null, null, undefined]);
  });

  test('re-totals the arms of the rows a filter left visible', () => {
    const el = list(true);
    updateTotalsRow(el.querySelector('.file_list_container')!);
    expect(el.querySelector('.t-totals__condition-num')!.textContent).toBe('4/');
  });
});

describe('choosing the primary criterion', () => {
  const meta = (overrides: Partial<CoverageData['meta']>): CoverageData['meta'] => ({ ...coverageData().meta, ...overrides });

  test('reads condition as a criterion name', () => {
    expect(normalizeCoverageType('condition')).toBe('condition');
  });

  test('honours a condition primary where conditions were measured', () => {
    expect(activeCoverageType(meta({ primary_coverage: 'condition', condition_coverage: true }))).toBe('condition');
  });

  test('ignores a condition primary where they were not', () => {
    expect(activeCoverageType(meta({ primary_coverage: 'condition' }))).toBe('line');
  });

  test('falls back to conditions where they are all a run measured', () => {
    expect(activeCoverageType(meta({ line_coverage: false, condition_coverage: true }))).toBe('condition');
  });

  test('falls back to methods where nothing at all was measured', () => {
    expect(activeCoverageType(meta({ line_coverage: false }))).toBe('method');
  });

  test('prefers methods to conditions in the fallback', () => {
    expect(activeCoverageType(meta({ line_coverage: false, method_coverage: true, condition_coverage: true }))).toBe('method');
  });

  test('answers the condition statistic', () => {
    expect(coverageStat({ conditions: stat(1, 2) }, 'condition')).toEqual(stat(1, 2));
  });

  test('falls back to the condition statistic last', () => {
    expect(primaryCoverageStat({ conditions: stat(1, 2) }, 'line')).toEqual(stat(1, 2));
  });
});

describe('the page with condition coverage', () => {
  async function boot(conditionCoverage: boolean): Promise<void> {
    installPageSkeleton();
    const page = coverageData();
    page.meta.condition_coverage = conditionCoverage;
    page.coverage = { [FILE]: data };
    await precomputeFileIds([FILE]);
    renderPage(page);
  }

  test('adds a legend row for missed conditions', async () => {
    await boot(true);
    expect(document.querySelector('.source-legend__row--condition')!.textContent).toBe('Missed condition');
  });

  test('gives the legend row the missed-condition swatch', async () => {
    await boot(true);
    expect(document.querySelector('.source-legend__row--condition .source-legend__swatch--missed-condition')).not.toBeNull();
  });

  test('adds no legend row where conditions were not measured', async () => {
    await boot(false);
    expect(document.querySelector('.source-legend__row--condition')).toBeNull();
  });

  test('opens a file with its condition annotations', async () => {
    await boot(true);
    expect(badges(materializeSourceFile(fileId(FILE))!.querySelectorAll('ol li')[0])).toHaveLength(2);
  });
});
