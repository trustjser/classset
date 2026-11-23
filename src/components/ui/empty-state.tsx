import React from 'react';
import { cn } from '@/lib/utils';

export type EmptyStateVariant = 'terms' | 'grades' | 'subjects' | 'assignments' | 'teachers' | 'groups';

interface EmptyStateProps {
  variant: EmptyStateVariant;
  title: string;
  description?: string;
  action?: React.ReactNode;
  className?: string;
}

const EmptyIllustration: React.FC<{ variant: EmptyStateVariant }> = ({ variant }) => {
  switch (variant) {
    case 'terms':
      return (
        <svg viewBox="0 0 180 124" className="h-[112px] w-[164px] shrink-0" aria-hidden="true">
          <ellipse cx="90" cy="108" rx="64" ry="8" fill="var(--color-selection)" />
          <path
            d="M34 74c-8-20 10-46 36-50 26-4 54 2 69 20 14 17 12 44-10 55-22 11-84 8-95-25Z"
            fill="var(--color-selection)"
          />
          {/* 日历主体 */}
          <rect x="48" y="30" width="84" height="68" rx="13" fill="var(--color-surface)" stroke="var(--color-border)" strokeWidth="2" />
          <path d="M48 43c0-7.2 5.8-13 13-13h58c7.2 0 13 5.8 13 13v5H48v-5Z" fill="var(--color-accent)" />
          {/* 顶部挂环 */}
          <rect x="65" y="22" width="6" height="14" rx="3" fill="var(--color-surface)" stroke="var(--color-accent)" strokeWidth="2" />
          <rect x="109" y="22" width="6" height="14" rx="3" fill="var(--color-surface)" stroke="var(--color-accent)" strokeWidth="2" />
          {/* 微笑表情 */}
          <circle cx="77" cy="64" r="3" fill="var(--color-ink)" />
          <circle cx="103" cy="64" r="3" fill="var(--color-ink)" />
          <circle cx="70" cy="69" r="3.5" fill="var(--color-warning-surface)" />
          <circle cx="110" cy="69" r="3.5" fill="var(--color-warning-surface)" />
          <path d="M84 69c2.5 3.5 9.5 3.5 12 0" fill="none" stroke="var(--color-ink)" strokeWidth="2.2" strokeLinecap="round" />
          {/* 日期小方块 */}
          <rect x="62" y="79" width="14" height="10" rx="3" fill="var(--color-selection)" />
          <rect x="83" y="79" width="14" height="10" rx="3" fill="var(--color-warning-surface)" />
          <rect x="104" y="79" width="14" height="10" rx="3" fill="var(--color-success-surface)" />
          {/* 漂浮小树叶/星星 */}
          <path d="M142 36l2.5 5 5 2.5-5 2.5-2.5 5-2.5-5-5-2.5 5-2.5Z" fill="var(--color-warning)" />
          <circle cx="38" cy="46" r="3.5" fill="var(--color-purple)" opacity="0.75" />
          <circle cx="144" cy="82" r="3" fill="var(--color-success)" opacity="0.75" />
        </svg>
      );

    case 'grades':
      return (
        <svg viewBox="0 0 180 124" className="h-[112px] w-[164px] shrink-0" aria-hidden="true">
          <ellipse cx="90" cy="108" rx="64" ry="8" fill="var(--color-selection)" />
          <path
            d="M36 74c-8-18 6-42 29-48 22-6 33-16 53-10 21 6 38 22 33 44-4 17-16 32-44 36-32 4-62-3-71-22Z"
            fill="var(--color-selection)"
          />
          {/* 小屋旗帜 */}
          <line x1="90" y1="16" x2="90" y2="32" stroke="var(--color-accent)" strokeWidth="2.5" strokeLinecap="round" />
          <path d="M90 17l17 5-17 5Z" fill="var(--color-warning)" />
          {/* 屋顶 */}
          <path
            d="M46 54 90 28l44 26"
            fill="none"
            stroke="var(--color-accent)"
            strokeWidth="4"
            strokeLinecap="round"
            strokeLinejoin="round"
          />
          {/* 教室主体 */}
          <rect x="54" y="50" width="72" height="50" rx="12" fill="var(--color-surface)" stroke="var(--color-border)" strokeWidth="2" />
          {/* 微笑表情 */}
          <circle cx="77" cy="68" r="3" fill="var(--color-ink)" />
          <circle cx="103" cy="68" r="3" fill="var(--color-ink)" />
          <circle cx="71" cy="73" r="3.5" fill="var(--color-warning-surface)" />
          <circle cx="109" cy="73" r="3.5" fill="var(--color-warning-surface)" />
          <path d="M84 73c2.5 3.5 9.5 3.5 12 0" fill="none" stroke="var(--color-ink)" strokeWidth="2.2" strokeLinecap="round" />
          {/* 小门/年级牌 */}
          <rect x="78" y="82" width="24" height="18" rx="6" fill="var(--color-selection)" stroke="var(--color-accent)" strokeWidth="1.6" />
          <circle cx="97" cy="91" r="1.6" fill="var(--color-accent)" />
          {/* 漂浮小卡片 */}
          <rect x="26" y="42" width="20" height="14" rx="4" transform="rotate(-10 26 42)" fill="var(--color-surface)" stroke="var(--color-border)" strokeWidth="1.6" />
          <line x1="30" y1="48" x2="40" y2="46.5" stroke="var(--color-purple)" strokeWidth="2" strokeLinecap="round" />
          {/* 闪光点缀 */}
          <path d="M144 34l2.5 5.5L152 42l-5.5 2.5L144 50l-2.5-5.5L136 42l5.5-2.5Z" fill="var(--color-accent)" opacity="0.8" />
          <circle cx="146" cy="78" r="3.5" fill="var(--color-success)" opacity="0.7" />
        </svg>
      );

    case 'subjects':
      return (
        <svg viewBox="0 0 180 124" className="h-[112px] w-[164px] shrink-0" aria-hidden="true">
          <ellipse cx="90" cy="108" rx="64" ry="8" fill="var(--color-selection)" />
          <path
            d="M32 68c-6-22 14-44 40-48 26-4 54 2 69 20 14 17 12 44-10 55-22 11-90 4-99-27Z"
            fill="var(--color-selection)"
          />
          {/* 课表矩阵板 */}
          <rect x="44" y="28" width="84" height="68" rx="12" fill="var(--color-surface)" stroke="var(--color-border)" strokeWidth="2" />
          <path d="M44 42c0-7.7 6.3-14 14-14h56c7.7 0 14 6.3 14 14v2H44v-2Z" fill="var(--color-table-header)" />
          {/* 科目彩色小圆点 */}
          <circle cx="58" cy="36" r="3" fill="var(--color-accent)" />
          <circle cx="68" cy="36" r="3" fill="var(--color-purple)" />
          <circle cx="78" cy="36" r="3" fill="var(--color-warning)" />
          {/* 矩阵格子 */}
          <rect x="54" y="52" width="18" height="12" rx="4" fill="var(--color-selection)" />
          <rect x="77" y="52" width="18" height="12" rx="4" fill="var(--color-table-header)" />
          <rect x="100" y="52" width="18" height="12" rx="4" fill="var(--color-success-surface)" />
          <rect x="54" y="69" width="18" height="12" rx="4" fill="var(--color-warning-surface)" />
          <rect x="77" y="69" width="18" height="12" rx="4" fill="var(--color-selection)" />
          <rect x="100" y="69" width="18" height="12" rx="4" fill="var(--color-table-header)" />
          {/* 可爱小铅笔角色 */}
          <g transform="translate(116 48) rotate(14)">
            <rect x="0" y="0" width="16" height="44" rx="5" fill="var(--color-accent)" />
            <rect x="0" y="0" width="16" height="9" rx="3" fill="var(--color-warning)" />
            <path d="M0 40h16l-8 12Z" fill="var(--color-surface)" stroke="var(--color-border)" strokeWidth="1.4" />
            <path d="M5.5 48.5h5L8 52Z" fill="var(--color-ink)" />
            <circle cx="5" cy="20" r="1.4" fill="var(--color-on-accent)" />
            <circle cx="11" cy="20" r="1.4" fill="var(--color-on-accent)" />
            <path d="M5.5 24c1.5 2 3.5 2 5 0" fill="none" stroke="var(--color-on-accent)" strokeWidth="1.5" strokeLinecap="round" />
          </g>
          {/* 闪光点缀 */}
          <path d="M32 34l2 4.5L38.5 40.5 34 42.5 32 47l-2-4.5L25.5 40.5 30 38.5Z" fill="var(--color-purple)" opacity="0.8" />
        </svg>
      );

    case 'assignments':
      return (
        <svg viewBox="0 0 180 124" className="h-[112px] w-[164px] shrink-0" aria-hidden="true">
          <ellipse cx="90" cy="108" rx="64" ry="8" fill="var(--color-selection)" />
          <path
            d="M35 76c-10-20 8-48 34-52 24-4 46-8 66 8 18 14 20 42 0 56-22 15-86 15-100-12Z"
            fill="var(--color-selection)"
          />
          {/* 课表卡片 */}
          <rect x="48" y="30" width="84" height="66" rx="12" fill="var(--color-surface)" stroke="var(--color-border)" strokeWidth="2" />
          {/* 顶部装订环 */}
          <rect x="64" y="24" width="6" height="12" rx="3" fill="var(--color-accent)" />
          <rect x="110" y="24" width="6" height="12" rx="3" fill="var(--color-accent)" />
          {/* 微笑卡片 */}
          <circle cx="76" cy="56" r="3" fill="var(--color-ink)" />
          <circle cx="104" cy="56" r="3" fill="var(--color-ink)" />
          <circle cx="69" cy="61" r="3.5" fill="var(--color-warning-surface)" />
          <circle cx="111" cy="61" r="3.5" fill="var(--color-warning-surface)" />
          <path d="M84 61c2.5 3.5 9.5 3.5 12 0" fill="none" stroke="var(--color-ink)" strokeWidth="2.2" strokeLinecap="round" />
          {/* 下方待填充条 */}
          <rect x="62" y="74" width="26" height="8" rx="4" fill="var(--color-selection)" />
          <rect x="92" y="74" width="26" height="8" rx="4" fill="var(--color-warning-surface)" />
          {/* 小铃铛点缀 */}
          <circle cx="138" cy="40" r="10" fill="var(--color-surface)" stroke="var(--color-border)" strokeWidth="1.6" />
          <path d="M138 35v5l3 2" fill="none" stroke="var(--color-accent)" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" />
          <path d="M36 44l2 4.5 4.5 2-4.5 2-2 4.5-2-4.5-4.5-2 4.5-2Z" fill="var(--color-warning)" />
        </svg>
      );

    case 'teachers':
      return (
        <svg viewBox="0 0 180 124" className="h-[112px] w-[164px] shrink-0" aria-hidden="true">
          <ellipse cx="90" cy="108" rx="64" ry="8" fill="var(--color-selection)" />
          <path
            d="M34 72c-8-22 10-46 36-50 26-4 54 2 69 20 14 17 12 44-10 55-22 11-84 8-95-25Z"
            fill="var(--color-selection)"
          />
          {/* 教师卡片主体 */}
          <rect x="54" y="34" width="72" height="64" rx="14" fill="var(--color-surface)" stroke="var(--color-border)" strokeWidth="2" />
          {/* 头像圆 */}
          <circle cx="90" cy="56" r="14" fill="var(--color-selection)" stroke="var(--color-accent)" strokeWidth="1.8" />
          {/* 可爱眼镜与笑脸 */}
          <circle cx="85" cy="55" r="3.5" fill="none" stroke="var(--color-ink)" strokeWidth="1.6" />
          <circle cx="95" cy="55" r="3.5" fill="none" stroke="var(--color-ink)" strokeWidth="1.6" />
          <line x1="88.5" y1="55" x2="91.5" y2="55" stroke="var(--color-ink)" strokeWidth="1.6" />
          <path d="M86 61.5c2 2.2 6 2.2 8 0" fill="none" stroke="var(--color-ink)" strokeWidth="1.6" strokeLinecap="round" />
          {/* 信息线条 */}
          <rect x="68" y="77" width="44" height="6" rx="3" fill="var(--color-table-header)" />
          <rect x="76" y="87" width="28" height="5" rx="2.5" fill="var(--color-selection)" />
          {/* 漂浮小书本 */}
          <g transform="translate(128 52) rotate(10)">
            <rect x="0" y="0" width="22" height="18" rx="4" fill="var(--color-accent)" />
            <line x1="11" y1="2" x2="11" y2="16" stroke="var(--color-on-accent)" strokeWidth="1.5" />
          </g>
          <path d="M40 36l2.5 5 5 2.5-5 2.5-2.5 5-2.5-5-5-2.5 5-2.5Z" fill="var(--color-accent)" opacity="0.8" />
          <circle cx="42" cy="80" r="3.5" fill="var(--color-warning)" opacity="0.85" />
        </svg>
      );

    case 'groups':
      return (
        <svg viewBox="0 0 180 124" className="h-[112px] w-[164px] shrink-0" aria-hidden="true">
          <ellipse cx="90" cy="108" rx="66" ry="8" fill="var(--color-selection)" />
          <path
            d="M30 72c-8-22 12-46 40-50 28-4 58 2 74 20 14 16 10 42-14 54-24 12-89 10-100-24Z"
            fill="var(--color-selection)"
          />
          {/* 连接弧线 */}
          <path
            d="M66 44c14-12 34-12 48 0"
            fill="none"
            stroke="var(--color-accent)"
            strokeWidth="2.2"
            strokeDasharray="4 4"
            strokeLinecap="round"
          />
          {/* 左边小伙伴卡片 */}
          <rect x="38" y="44" width="46" height="50" rx="12" fill="var(--color-surface)" stroke="var(--color-border)" strokeWidth="2" />
          <circle cx="61" cy="60" r="9" fill="var(--color-selection)" stroke="var(--color-accent)" strokeWidth="1.6" />
          <circle cx="58" cy="59.5" r="1.4" fill="var(--color-ink)" />
          <circle cx="64" cy="59.5" r="1.4" fill="var(--color-ink)" />
          <path d="M58.5 63c1.5 1.8 3.5 1.8 5 0" fill="none" stroke="var(--color-ink)" strokeWidth="1.4" strokeLinecap="round" />
          <rect x="49" y="75" width="24" height="5" rx="2.5" fill="var(--color-table-header)" />
          <rect x="53" y="83" width="16" height="4" rx="2" fill="var(--color-selection)" />
          {/* 右边小伙伴卡片 */}
          <rect x="96" y="44" width="46" height="50" rx="12" fill="var(--color-surface)" stroke="var(--color-border)" strokeWidth="2" />
          <circle cx="119" cy="60" r="9" fill="var(--color-warning-surface)" stroke="var(--color-warning)" strokeWidth="1.6" />
          <circle cx="116" cy="59.5" r="1.4" fill="var(--color-ink)" />
          <circle cx="122" cy="59.5" r="1.4" fill="var(--color-ink)" />
          <path d="M116.5 63c1.5 1.8 3.5 1.8 5 0" fill="none" stroke="var(--color-ink)" strokeWidth="1.4" strokeLinecap="round" />
          <rect x="107" y="75" width="24" height="5" rx="2.5" fill="var(--color-table-header)" />
          <rect x="111" y="83" width="16" height="4" rx="2" fill="var(--color-warning-surface)" />
          {/* 中间小星星 */}
          <path d="M90 26l2.5 5.5L98 34l-5.5 2.5L90 42l-2.5-5.5L82 34l5.5-2.5Z" fill="var(--color-purple)" />
          <circle cx="148" cy="36" r="3" fill="var(--color-success)" opacity="0.75" />
        </svg>
      );
  }
};

export const EmptyState: React.FC<EmptyStateProps> = ({
  variant,
  title,
  description,
  action,
  className,
}) => (
  <div
    className={cn(
      'flex flex-col items-center justify-center px-6 py-12 text-center',
      className,
    )}
  >
    <EmptyIllustration variant={variant} />
    <h3 className="mt-3 text-[14.5px] font-semibold text-ink">{title}</h3>
    {description && (
      <p className="mt-1.5 max-w-sm text-[12.5px] leading-relaxed text-ink-secondary">
        {description}
      </p>
    )}
    {action && <div className="mt-4">{action}</div>}
  </div>
);
