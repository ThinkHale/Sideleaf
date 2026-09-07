type BrandVariant = 'logo' | 'tagline' | 'wordmark' | 'icon';
const assets: Record<BrandVariant, string> = {
  logo: '/brand/sideleaf-logo.png',
  tagline: '/brand/sideleaf-logo-tagline.png',
  wordmark: '/brand/sideleaf-wordmark.png',
  icon: '/brand/sideleaf-icon.png',
};

export function Brand({
  name = 'Sideleaf',
  variant = 'logo',
  className = '',
}: {
  name?: string;
  variant?: BrandVariant;
  className?: string;
}) {
  if (name !== 'Sideleaf' && variant !== 'icon')
    return <span className={`brand-custom ${className}`}>{name}</span>;
  return (
    <img
      className={`brand-art brand-art-${variant} ${className}`}
      src={assets[variant]}
      alt={variant === 'tagline' ? `${name}. Good notes. Better Questions.` : name}
      width={variant === 'icon' ? 1254 : 2172}
      height={variant === 'icon' ? 1254 : 724}
      draggable={false}
    />
  );
}
