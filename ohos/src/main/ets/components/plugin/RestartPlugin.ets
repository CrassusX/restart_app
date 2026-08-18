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
import { common, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@ohos.base';

/**
 * OHOS implementation for the `restart` platform channel.
 *
 * OHOS provides an application-level restart API that relaunches the current
 * UIAbility with a clean process lifecycle. In-process Flutter engine restart
 * is not available to a plugin without host application cooperation.
 */
export default class RestartPlugin implements FlutterPlugin, MethodCallHandler, AbilityAware {
  private static readonly LOG_DOMAIN: number = 0x5241;
  private static readonly LOG_TAG: string = 'restart_app';
  private channel: MethodChannel | null = null;
  private abilityContext: common.UIAbilityContext | null = null;

  constructor() {
    this.log('constructor');
  }

  private log(message: string): void {
    hilog.info(RestartPlugin.LOG_DOMAIN, RestartPlugin.LOG_TAG, '%{public}s', message);
  }

  private logError(message: string): void {
    hilog.error(RestartPlugin.LOG_DOMAIN, RestartPlugin.LOG_TAG, '%{public}s', message);
  }

  getUniqueClassName(): string {
    this.log('getUniqueClassName');
    return 'RestartPlugin';
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.log('onAttachedToEngine: creating MethodChannel(restart)');
    this.channel = new MethodChannel(binding.getBinaryMessenger(), 'restart');
    this.channel.setMethodCallHandler(this);
    this.log('onAttachedToEngine: MethodChannel handler registered');
  }

  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    this.log('onDetachedFromEngine');
    if (this.channel != null) {
      this.channel.setMethodCallHandler(null);
      this.channel = null;
    }
    this.abilityContext = null;
  }

  onAttachedToAbility(binding: AbilityPluginBinding): void {
    this.abilityContext = binding.getAbility().context;
    const abilityInfo = this.abilityContext.abilityInfo;
    this.log(
      `onAttachedToAbility: bundle=${abilityInfo.bundleName}, module=${abilityInfo.moduleName}, ability=${abilityInfo.name}`,
    );
  }

  onDetachedFromAbility(): void {
    this.log('onDetachedFromAbility');
    this.abilityContext = null;
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    this.log(`onMethodCall: method=${call.method}`);
    switch (call.method) {
      case 'restartCapability':
        result.success(this.capabilityPayload());
        break;
      case 'restartApp':
        this.handleRestartApp(call, result);
        break;
      default:
        this.logError(`onMethodCall: unsupported method=${call.method}`);
        result.notImplemented();
    }
  }

  private handleRestartApp(call: MethodCall, result: MethodResult): void {
    const modeValue = call.argument('mode') as string | undefined;
    const mode = typeof modeValue === 'string' ? modeValue : 'platformDefault';
    const structuredResult = call.argument('structuredResult') as boolean | undefined;
    const forceKill = call.argument('forceKill') as boolean | undefined;
    this.log(
      `handleRestartApp: mode=${mode}, structuredResult=${structuredResult}, forceKill=${forceKill}`,
    );

    // OHOS only exposes a full process restart. `flutterEngine` and
    // `notificationFallback` have no OHOS implementation.
    if (mode !== 'platformDefault' && mode !== 'process') {
      this.logError(`handleRestartApp: unsupported mode=${mode}`);
      result.error(
        'UNSUPPORTED_RESTART_MODE',
        `Restart mode '${mode}' is not supported on OHOS.`,
        null,
      );
      return;
    }

    const abilityContext = this.abilityContext;
    if (abilityContext == null) {
      this.logError('handleRestartApp: abilityContext is null');
      result.error('RESTART_FAILED', 'No ability context available.', null);
      return;
    }

    const resolvedMode = mode === 'process' || forceKill ? 'process' : 'platformDefault';
    this.log(`handleRestartApp: accepted, resolvedMode=${resolvedMode}`);

    // Return before restarting so the platform channel response reaches Dart.
    if (structuredResult === true) {
      const payload: Map<string, Object> = new Map<string, Object>();
      payload.set('success', true as Object);
      payload.set('mode', resolvedMode as Object);
      result.success(payload);
    } else {
      result.success('ok');
    }
    this.log('handleRestartApp: result returned to Flutter, scheduling restart');

    setTimeout(() => {
      this.log('handleRestartApp: restart timer fired');
      this.performRestart(abilityContext);
    }, 300);
  }

  private performRestart(abilityContext: common.UIAbilityContext): void {
    const abilityInfo = abilityContext.abilityInfo;
    const want: Want = {
      bundleName: abilityInfo.bundleName,
      moduleName: abilityInfo.moduleName,
      abilityName: abilityInfo.name,
    };
    this.log(
      `performRestart: want bundle=${want.bundleName}, module=${want.moduleName}, ability=${want.abilityName}`,
    );

    try {
      const appContext = abilityContext.getApplicationContext();
      this.log('performRestart: applicationContext acquired, calling restartApp');
      appContext.restartApp(want);
      this.log('performRestart: restartApp returned without synchronous error');
    } catch (err) {
      const restartError = err as BusinessError;
      this.logError(
        `performRestart: restartApp failed, code=${restartError.code}, message=${restartError.message}`,
      );
    }
  }

  private capabilityPayload(): Map<string, Object> {
    const ready = this.abilityContext != null;
    this.log(`capabilityPayload: abilityReady=${ready}`);
    const payload: Map<string, Object> = new Map<string, Object>();
    payload.set('fullProcessRestart', ready as Object);
    payload.set('flutterEngineRestart', false as Object);
    payload.set('notificationFallback', false as Object);
    payload.set('engineRestartConfigured', false as Object);
    payload.set('platformDefaultMode', 'process' as Object);
    payload.set(
      'reason',
      (ready
        ? 'OHOS restarts via ApplicationContext.restartApp. Flutter engine restart is not supported because a plugin cannot rebuild the ability view without host app cooperation.'
        : 'No ability context available yet.') as Object,
    );
    return payload;
  }
}
