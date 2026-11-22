export interface RoutineTemplate {
  id: string;
  name: string;
  description: string;
  teachingWeekdays: readonly number[];
  periods: readonly {
    name: string;
    times: readonly (readonly [string, string])[];
  }[];
}

const weekdays = [1, 2, 3, 4, 5] as const;

export const ROUTINE_TEMPLATES: readonly RoutineTemplate[] = [
  {
    id: 'primary_day',
    name: '小学走读',
    description: '40 分钟课时，第一节 8:20 开始，符合小学上课时间不早于 8:20 的要求。',
    teachingWeekdays: weekdays,
    periods: [
      { name: '上午', times: [['08:20', '09:00'], ['09:10', '09:50'], ['10:20', '11:00'], ['11:10', '11:50']] },
      { name: '下午', times: [['14:00', '14:40'], ['14:50', '15:30'], ['15:40', '16:20']] },
    ],
  },
  {
    id: 'junior_day',
    name: '初中走读',
    description: '45 分钟课时，早读 + 上午 4 节 + 下午 3 节，第一节 8:00 开始。',
    teachingWeekdays: weekdays,
    periods: [
      { name: '早上', times: [['07:40', '08:00']] },
      { name: '上午', times: [['08:00', '08:45'], ['08:55', '09:40'], ['10:10', '10:55'], ['11:05', '11:50']] },
      { name: '下午', times: [['14:00', '14:45'], ['14:55', '15:40'], ['15:50', '16:35']] },
    ],
  },
  {
    id: 'junior_boarding',
    name: '初中寄宿',
    description: '早读 + 上午 4 节 + 下午 4 节 + 晚自习 2 节，适合寄宿制初中。',
    teachingWeekdays: weekdays,
    periods: [
      { name: '早上', times: [['07:40', '08:00']] },
      { name: '上午', times: [['08:00', '08:45'], ['08:55', '09:40'], ['10:10', '10:55'], ['11:05', '11:50']] },
      { name: '下午', times: [['14:00', '14:45'], ['14:55', '15:40'], ['15:50', '16:35'], ['16:45', '17:30']] },
      { name: '晚上', times: [['19:00', '19:45'], ['19:55', '20:40']] },
    ],
  },
  {
    id: 'senior_boarding',
    name: '高中寄宿',
    description: '早读 + 上午 4 节 + 下午 4 节 + 晚自习 3 节，适合寄宿制高中。',
    teachingWeekdays: weekdays,
    periods: [
      { name: '早上', times: [['07:20', '07:50']] },
      { name: '上午', times: [['08:00', '08:45'], ['08:55', '09:40'], ['10:10', '10:55'], ['11:05', '11:50']] },
      { name: '下午', times: [['14:10', '14:55'], ['15:05', '15:50'], ['16:00', '16:45'], ['16:55', '17:40']] },
      { name: '晚上', times: [['19:00', '19:45'], ['19:55', '20:40'], ['20:50', '21:35']] },
    ],
  },
];

export function templateSummary(template: RoutineTemplate): string {
  return template.periods
    .filter((period) => period.times.length > 0)
    .map((period) => (period.name === '早上' ? '早读' : period.name) + ' ' + period.times.length + ' 节')
    .join(' · ');
}
