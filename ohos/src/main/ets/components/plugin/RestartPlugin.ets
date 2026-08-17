import {
  FlutterPlugin,
  FlutterPluginBinding,
  MethodCall,
  MethodCallHandler,
  MethodChannel,
  MethodResult,
  AbilityAware,
  AbilityPluginBinding,
} from '@ohos/flutter_ohos';
import common from '@ohos.app.ability.common';
import Want from '@ohos.app.ability.Want';
import BusinessError from '@ohos.base.BusinessError';
import { deviceInfo } from '@kit.BasicServicesKit';

/**
 * OHOS (OpenHarmony / HarmonyOS NEXT) implementation for the `restart`
 * platform channel.
 *
 * The restart path combines the logic used by the Android and iOS targets:
 *
 *  - Android-style full process relaunch: the preferred path uses the native
 *    `ApplicationContext.restartApp(want)` API (API 12+), which restarts the
 *    process and relaunches the configured UIAbility, giving a clean cold
 *    start like the Android `forceKill` path. On API levels below 12 the
 *    plugin falls back to `startAbility(want)` followed by
 *    `terminateSelf()`.
 *  - iOS-style in-process Flutter engine restart is not available here: a
 *    plugin cannot rebuild the ability's engine and view without host app
 *    cooperation, so it is reported as unsupported (mirroring how iOS
 *    reports full process restart as unsupported).
 */
export default class RestartPlugin implements FlutterPlugin, MethodCallHandler, AbilityAware {
  private channel: MethodChannel | null = null;
  private abilityContext: common.UIAbilityContext | null = null;

  constructor() {
  }

  getUniqueClassName(): string {
    return 'RestartPlugin';
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.channel = new MethodChannel(binding.getBinaryMessenger(), 'restart');
    this.channel.setMethodCallHandler(this);
  }

  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    if (this.channel != null) {
      this.channel.setMethodCallHandler(null);
      this.channel = null;
    }
    this.abilityContext = null;
  }

  onAttachedToAbility(binding: AbilityPluginBinding): void {
    this.abilityContext = binding.getAbility().context;
  }

  onDetachedFromAbility(): void {
    this.abilityContext = null;
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    switch (call.method) {
      case 'restartCapability':
        result.success(this.capabilityPayload());
        break;
      case 'restartApp':
        this.handleRestartApp(call, result);
        break;
      default:
        result.notImplemented();
    }
  }

  private handleRestartApp(call: MethodCall, result: MethodResult): void {
    const args = (call.arguments ?? {}) as Record<string, Object | boolean | string | null | undefined>;
    const modeValue = args['mode'];
    const mode = typeof modeValue === 'string' ? modeValue : 'platformDefault';
    const structuredResult = args['structuredResult'] === true;
    const forceKill = args['forceKill'] === true;

    // OHOS only exposes a full process restart. `flutterEngine` and
    // `notificationFallback` have no OHOS implementation.
    if (mode !== 'platformDefault' && mode !== 'process') {
      result.error(
        'UNSUPPORTED_RESTART_MODE',
        `Restart mode '${mode}' is not supported on OHOS.`,
        null,
      );
      return;
    }

    const abilityContext = this.abilityContext;
    if (abilityContext == null) {
      result.error('RESTART_FAILED', 'No ability context available.', null);
      return;
    }

    const resolvedMode = mode === 'process' || forceKill ? 'process' : 'platformDefault';

    // Reply before the destructive work so the platform channel result can
    // cross the bridge before the process is torn down. This mirrors the
    // delay used by the Android implementation.
    if (structuredResult) {
      result.success({
        success: true,
        mode: resolvedMode,
      });
    } else {
      result.success('ok');
    }

    setTimeout(() => {
      this.performRestart(abilityContext, resolvedMode);
    }, 300);
  }

  private performRestart(
    abilityContext: common.UIAbilityContext,
    mode: 'platformDefault' | 'process',
  ): void {
    const want: Want = {
      bundleName: abilityContext.abilityInfo.bundleName,
      abilityName: abilityContext.abilityInfo.name,
      moduleName: abilityContext.abilityInfo.moduleName,
    };

    // `platformDefault` and `process` both map to a full process relaunch on
    // OHOS, which matches Android's cold-start behavior. The `mode` value only
    // influences the payload returned to Dart; the native restart remains a full
    // app restart.
    if (deviceInfo.sdkApiVersion >= 12) {
      const appContext = abilityContext.getApplicationContext() as common.ApplicationContext;
      try {
        appContext.restartApp(want);
        return;
      } catch (err) {
        const restartError = err as BusinessError;
        console.error(
          `[restart_app] ApplicationContext.restartApp failed: ${restartError.message}`,
        );
        // Fall through to the startAbility + terminateSelf path.
      }
    }

    // Fallback (API < 12 or restartApp failure): launch the ability again,
    // then terminate the current one.
    abilityContext.startAbility(want)
      .then(() => {
        return abilityContext.terminateSelf();
      })
      .catch((err: BusinessError) => {
        console.error(`[restart_app] startAbility/terminateSelf failed: ${err.message}`);
      });
  }

  private capabilityPayload(): Record<string, Object> {
    const ready = this.abilityContext != null;
    return {
      fullProcessRestart: ready,
      flutterEngineRestart: false,
      notificationFallback: false,
      engineRestartConfigured: false,
      platformDefaultMode: 'process',
      reason: ready
        ? 'OHOS restarts via ApplicationContext.restartApp (API 12+) with a startAbility + terminateSelf fallback. Flutter engine restart is not supported because a plugin cannot rebuild the ability view without host app cooperation.'
        : 'No ability context available yet.',
    };
  }
}
