export function getSafariInstallTarget(
  userAgent: string,
  maxTouchPoints: number,
  standalone: boolean
): 'dock' | 'home-screen' | null {
  if (standalone || !/Version\/[\d.]+.*Safari\//i.test(userAgent)) return null;
  if (/iPad|iPhone|iPod/i.test(userAgent)) return 'home-screen';
  if (/Macintosh/i.test(userAgent)) {
    return maxTouchPoints > 1 ? 'home-screen' : 'dock';
  }
  return null;
}
