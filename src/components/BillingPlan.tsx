import { useEffect, useState } from 'react';
import { CreditCard, RefreshCw } from 'lucide-react';
import { api, type ProductConfig } from '../api';

type BillingState = {
  plan: 'free' | 'pro';
  provider: 'stripe' | 'apple' | 'google' | null;
  status: string;
  currentPeriodEnd: string | null;
  cancelAtPeriodEnd: boolean;
  paymentReview: boolean;
  checkoutReady: boolean;
  portalReady: boolean;
  mode: 'test' | 'live';
  price: { amount: number; currency: string; interval: string };
  message: string | null;
};
type CaptureUsage = {
  plan: 'free' | 'pro';
  usedSeconds: number;
  remainingSeconds: number | null;
  meetingLimitSeconds: number | null;
  resetAt: string;
  activeSessionId: string | null;
};
type PlanData = { billing: BillingState; usage: CaptureUsage };

function duration(seconds: number) {
  const rounded = Math.max(0, Math.floor(seconds));
  const minutes = Math.floor(rounded / 60);
  const remainder = rounded % 60;
  return `${minutes} min${remainder ? ` ${remainder} sec` : ''}`;
}

function calendarDate(value: string) {
  return new Date(value).toLocaleString(undefined, {
    month: 'short',
    day: 'numeric',
    year: 'numeric',
    hour: 'numeric',
    minute: '2-digit',
    timeZoneName: 'short',
  });
}

export function BillingPlan({ config }: { config: ProductConfig }) {
  const [data, setData] = useState<PlanData | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [pending, setPending] = useState<'checkout' | 'portal' | null>(null);
  const [refresh, setRefresh] = useState(0);
  const [billingReturn] = useState(() =>
    new URLSearchParams(window.location.search).get('billing'),
  );

  useEffect(() => {
    const controller = new AbortController();
    const signal = AbortSignal.any([controller.signal, AbortSignal.timeout(15000)]);
    setLoading(true);
    setError('');
    void Promise.all([
      api<BillingState>('/billing', { signal }),
      api<CaptureUsage>('/capture/usage', { signal }),
    ])
      .then(([billing, usage]) => {
        if (!controller.signal.aborted) setData({ billing, usage });
      })
      .catch(() => {
        if (!controller.signal.aborted) {
          setData(null);
          setError('We could not load your plan and usage. Your notes are still available.');
        }
      })
      .finally(() => {
        if (!controller.signal.aborted) setLoading(false);
      });
    return () => controller.abort();
  }, [refresh]);

  useEffect(() => {
    const reload = () => setRefresh((value) => value + 1);
    const visible = () => {
      if (document.visibilityState === 'visible') reload();
    };
    window.addEventListener('focus', reload);
    window.addEventListener('pageshow', reload);
    document.addEventListener('visibilitychange', visible);
    return () => {
      window.removeEventListener('focus', reload);
      window.removeEventListener('pageshow', reload);
      document.removeEventListener('visibilitychange', visible);
    };
  }, []);

  useEffect(() => {
    if (billingReturn !== 'success' || loading || data?.billing.plan === 'pro' || refresh >= 6) {
      return;
    }
    const timer = window.setTimeout(() => setRefresh((value) => value + 1), 2000);
    return () => window.clearTimeout(timer);
  }, [billingReturn, loading, data?.billing.plan, refresh]);

  async function openBilling(destination: 'checkout' | 'portal') {
    if (pending || loading) return;
    setPending(destination);
    setError('');
    try {
      const response = await api<{ url: string }>(`/billing/${destination}`, {
        method: 'POST',
        body: JSON.stringify({}),
      });
      const url = new URL(response.url);
      const expectedHost =
        destination === 'checkout' ? 'checkout.stripe.com' : 'billing.stripe.com';
      if (url.origin !== `https://${expectedHost}` || url.username || url.password) {
        throw new Error('The billing link could not be verified. Please try again.');
      }
      window.location.assign(url.href);
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : 'Billing could not be opened. Try again.');
      setPending(null);
    }
  }

  const billing = data?.billing;
  const usage = data?.usage;
  const proPrice = billing
    ? new Intl.NumberFormat(undefined, {
        style: 'currency',
        currency: billing.price.currency,
        maximumFractionDigits: 2,
      }).format(billing.price.amount)
    : null;
  const existingPurchase =
    Boolean(billing?.provider) &&
    billing?.status !== 'canceled' &&
    billing?.status !== 'incomplete_expired';

  return (
    <section className="settings-section billing-section" aria-label="Plan and usage">
      <div className="billing-heading">
        <h3>Plan & usage</h3>
        <button
          className="text-button"
          onClick={() => setRefresh((value) => value + 1)}
          disabled={loading || pending !== null}
        >
          <RefreshCw size={14} />
          {loading ? 'Refreshing' : 'Refresh status'}
        </button>
      </div>
      {loading && <p role="status">Loading your plan and usage...</p>}
      {error && (
        <p className="error" role="alert">
          {error}
        </p>
      )}
      {billing && usage && (
        <>
          {billing.mode === 'test' && (billing.checkoutReady || billing.portalReady) && (
            <div className="notice billing-test">
              Test mode. Checkout uses Stripe test payments. No real payment is collected.
            </div>
          )}
          <div className="billing-current">
            <strong>Current plan: {billing.plan === 'pro' ? 'Pro' : 'Free'}</strong>
            {billing.plan === 'pro' && billing.currentPeriodEnd && (
              <small>
                {billing.cancelAtPeriodEnd ? 'Pro access ends' : 'Renews'}{' '}
                {calendarDate(billing.currentPeriodEnd)}
                {billing.cancelAtPeriodEnd ? '. Your notes stay available on Free.' : '.'}
              </small>
            )}
            {billing.status === 'past_due' && (
              <p>Payment is overdue. Update your payment method to restore Pro.</p>
            )}
            {billing.paymentReview && (
              <p>Pro access is paused while a refunded or disputed payment is reviewed.</p>
            )}
            {['incomplete', 'unpaid', 'paused'].includes(billing.status) &&
              !billing.paymentReview && (
                <p>Your subscription needs attention. Open billing to review the payment status.</p>
              )}
          </div>
          {billingReturn === 'success' && billing.plan !== 'pro' && (
            <div className="notice" role="status">
              Waiting for payment confirmation. Pro activates when Stripe confirms the subscription.
              You can refresh this status in a moment.
            </div>
          )}
          {billingReturn === 'canceled' && (
            <p>Checkout was closed. Your current plan is shown above.</p>
          )}
          <div className="billing-usage">
            <strong>Live transcription this month</strong>
            <dl>
              <div>
                <dt>Used</dt>
                <dd>{duration(usage.usedSeconds)}</dd>
              </div>
              <div>
                <dt>Remaining</dt>
                <dd>
                  {usage.remainingSeconds === null ? 'Unlimited' : duration(usage.remainingSeconds)}
                </dd>
              </div>
            </dl>
            {usage.remainingSeconds !== null && (
              <progress
                aria-label="Monthly live transcription usage"
                value={usage.usedSeconds}
                max={Math.max(usage.usedSeconds + usage.remainingSeconds, 1)}
              />
            )}
            <small>
              Resets {calendarDate(usage.resetAt)}.
              {usage.meetingLimitSeconds !== null &&
                ` Up to ${duration(usage.meetingLimitSeconds)} per meeting.`}
              {usage.activeSessionId && ' A live session is active. Refresh for its latest usage.'}
            </small>
          </div>
          <div className="plan-row billing-plans">
            <div className={billing.plan === 'free' ? 'current' : ''}>
              <strong>Free</strong>
              <p>
                Unlimited ordinary notes
                <br />
                {config.freeMinutes} live transcription minutes per month
                <br />
                {config.meetingMinutes} minutes per meeting
              </p>
            </div>
            <div className={billing.plan === 'pro' ? 'current' : ''}>
              <strong>
                Pro · {proPrice}/{billing.price.interval}
              </strong>
              <p>
                Unlimited live transcription minutes
                <br />
                One active session at a time
                <br />
                Your plan follows your Sideleaf account
              </p>
            </div>
          </div>
          {billing.message && <p>{billing.message}</p>}
          <div className="billing-actions">
            {billing.plan !== 'pro' && !existingPurchase && (
              <button
                className="primary"
                disabled={!billing.checkoutReady || loading || pending !== null}
                onClick={() => void openBilling('checkout')}
              >
                <CreditCard size={16} />
                {pending === 'checkout'
                  ? 'Opening checkout...'
                  : billing.mode === 'test' && billing.checkoutReady
                    ? 'Test Pro checkout'
                    : 'Upgrade to Pro'}
              </button>
            )}
            {billing.portalReady && (
              <button
                disabled={loading || pending !== null}
                onClick={() => void openBilling('portal')}
              >
                <CreditCard size={16} />
                {pending === 'portal' ? 'Opening billing...' : 'Manage subscription'}
              </button>
            )}
          </div>
          <small>Ordinary notes stay free, even when your transcription allowance runs out.</small>
        </>
      )}
    </section>
  );
}
