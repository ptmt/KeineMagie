import React, { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import {
  ActivityIndicator,
  KeyboardAvoidingView,
  Modal,
  Platform,
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  TextInput,
  View,
} from 'react-native';
import { StatusBar } from 'expo-status-bar';
import { AudioPlayer, AudioStatus, createAudioPlayer, setAudioModeAsync } from 'expo-audio';
import * as FileSystem from 'expo-file-system';
import { SafeAreaProvider, SafeAreaView, useSafeAreaInsets } from 'react-native-safe-area-context';

type Mode = 'full' | 'sentence';

type FetchState = 'idle' | 'loading' | 'error';

const DEFAULT_RATE = 0.95;
const DEFAULT_GAP_SECONDS = 1.2;
const DEFAULT_REPEAT_COUNT = 2;
const DEFAULT_LOOP_COUNT = 0;
const DEFAULT_LANGUAGE = 'de-DE';
const DEFAULT_SERVER_URL = 'http://localhost:8787';
const DEFAULT_TTS_MODEL = 'gpt-4o-mini-tts';
const DEFAULT_TTS_VOICE = 'alloy';
const DEFAULT_TTS_FORMAT = 'mp3';
const DEFAULT_INSTRUCTIONS = 'Speak clearly with neutral diction.';

const LANGUAGE_OPTIONS = [
  { code: 'de-DE', label: 'German' },
  { code: 'en-US', label: 'English (US)' },
  { code: 'en-GB', label: 'English (UK)' },
  { code: 'es-ES', label: 'Spanish' },
  { code: 'fr-FR', label: 'French' },
  { code: 'it-IT', label: 'Italian' },
  { code: 'pt-BR', label: 'Portuguese (BR)' },
  { code: 'ru-RU', label: 'Russian' },
  { code: 'ja-JP', label: 'Japanese' },
  { code: 'ko-KR', label: 'Korean' },
  { code: 'zh-CN', label: 'Chinese (CN)' },
];

const OPENAI_VOICES = [
  { id: 'alloy', label: 'Alloy' },
  { id: 'ash', label: 'Ash' },
  { id: 'ballad', label: 'Ballad' },
  { id: 'coral', label: 'Coral' },
  { id: 'echo', label: 'Echo' },
  { id: 'fable', label: 'Fable' },
  { id: 'nova', label: 'Nova' },
  { id: 'onyx', label: 'Onyx' },
  { id: 'sage', label: 'Sage' },
  { id: 'shimmer', label: 'Shimmer' },
  { id: 'verse', label: 'Verse' },
];

const normalizeWhitespace = (value: string) => value.replace(/\s+/g, ' ').trim();

const decodeEntities = (value: string) =>
  value
    .replace(/&nbsp;/gi, ' ')
    .replace(/&amp;/gi, '&')
    .replace(/&quot;/gi, '"')
    .replace(/&#39;/gi, "'")
    .replace(/&lt;/gi, '<')
    .replace(/&gt;/gi, '>');

const extractTextFromHtml = (html: string) => {
  const withoutScripts = html.replace(/<script[\s\S]*?<\/script>/gi, ' ');
  const withoutStyles = withoutScripts.replace(/<style[\s\S]*?<\/style>/gi, ' ');
  const withoutTags = withoutStyles.replace(/<[^>]+>/g, ' ');
  return normalizeWhitespace(decodeEntities(withoutTags));
};

const splitIntoSentences = (text: string) => {
  const normalized = normalizeWhitespace(text);
  if (!normalized) return [];
  const matches = normalized.match(/[^.!?]+[.!?]+|[^.!?]+$/g);
  return matches ? matches.map((sentence) => sentence.trim()).filter(Boolean) : [normalized];
};

const countWords = (text: string) => {
  const normalized = normalizeWhitespace(text);
  if (!normalized) return 0;
  return normalized.split(' ').length;
};

const parsePositiveInt = (value: string, fallback: number) => {
  const parsed = Number.parseInt(value, 10);
  if (Number.isNaN(parsed) || parsed < 0) return fallback;
  return parsed;
};

const parseFloatSafe = (value: string, fallback: number) => {
  const parsed = Number.parseFloat(value);
  if (Number.isNaN(parsed) || parsed < 0) return fallback;
  return parsed;
};

const clamp = (value: number, min: number, max: number) => Math.min(max, Math.max(min, value));

const chunkText = (text: string, maxLength: number) => {
  if (text.length <= maxLength) return [text];
  const sentences = splitIntoSentences(text);
  const chunks: string[] = [];
  let current = '';

  const pushCurrent = () => {
    const trimmed = current.trim();
    if (trimmed) chunks.push(trimmed);
    current = '';
  };

  const addSentence = (sentence: string) => {
    if (sentence.length > maxLength) {
      const words = sentence.split(/\s+/g);
      for (const word of words) {
        const candidate = current ? `${current} ${word}` : word;
        if (candidate.length > maxLength) {
          pushCurrent();
          current = word;
        } else {
          current = candidate;
        }
      }
      pushCurrent();
      return;
    }

    const candidate = current ? `${current} ${sentence}` : sentence;
    if (candidate.length > maxLength) {
      pushCurrent();
      current = sentence;
    } else {
      current = candidate;
    }
  };

  sentences.forEach(addSentence);
  pushCurrent();

  return chunks.length ? chunks : [text];
};

const sleep = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));

const simpleHash = (value: string) => {
  let hashA = 0xdeadbeef;
  let hashB = 0x41c6ce57;
  for (let i = 0; i < value.length; i += 1) {
    const code = value.charCodeAt(i);
    hashA = Math.imul(hashA ^ code, 2654435761);
    hashB = Math.imul(hashB ^ code, 1597334677);
  }
  hashA = (hashA ^ (hashA >>> 16)) >>> 0;
  hashB = (hashB ^ (hashB >>> 16)) >>> 0;
  return `${hashA.toString(16)}${hashB.toString(16)}`;
};

const arrayBufferToBase64 = (buffer: ArrayBuffer) => {
  const bytes = new Uint8Array(buffer);
  const base64Chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
  let result = '';
  for (let i = 0; i < bytes.length; i += 3) {
    const a = bytes[i];
    const b = i + 1 < bytes.length ? bytes[i + 1] : 0;
    const c = i + 2 < bytes.length ? bytes[i + 2] : 0;
    const triple = (a << 16) | (b << 8) | c;
    result += base64Chars[(triple >> 18) & 63];
    result += base64Chars[(triple >> 12) & 63];
    result += i + 1 < bytes.length ? base64Chars[(triple >> 6) & 63] : '=';
    result += i + 2 < bytes.length ? base64Chars[triple & 63] : '=';
  }
  return result;
};

function AppContent() {
  const insets = useSafeAreaInsets();
  const [mode, setMode] = useState<Mode>('full');
  const [draftText, setDraftText] = useState('');
  const [activeText, setActiveText] = useState('');
  const [attemptText, setAttemptText] = useState('');
  const [urlInput, setUrlInput] = useState('');
  const [fetchState, setFetchState] = useState<FetchState>('idle');
  const [fetchError, setFetchError] = useState<string | null>(null);
  const [repeatCountInput, setRepeatCountInput] = useState(`${DEFAULT_REPEAT_COUNT}`);
  const [loopCountInput, setLoopCountInput] = useState(`${DEFAULT_LOOP_COUNT}`);
  const [gapSecondsInput, setGapSecondsInput] = useState(`${DEFAULT_GAP_SECONDS}`);
  const [rateInput, setRateInput] = useState(`${DEFAULT_RATE}`);
  const [selectedLanguage, setSelectedLanguage] = useState(DEFAULT_LANGUAGE);
  const [selectedVoiceId, setSelectedVoiceId] = useState(DEFAULT_TTS_VOICE);
  const [ttsModel, setTtsModel] = useState(DEFAULT_TTS_MODEL);
  const [serverUrl, setServerUrl] = useState(DEFAULT_SERVER_URL);
  const [serverAuthToken, setServerAuthToken] = useState('');
  const [instructionsInput, setInstructionsInput] = useState(DEFAULT_INSTRUCTIONS);
  const [isPlaying, setIsPlaying] = useState(false);
  const [isPaused, setIsPaused] = useState(false);
  const [isFetchingAudio, setIsFetchingAudio] = useState(false);
  const [isPracticeExpanded, setIsPracticeExpanded] = useState(false);
  const [playbackError, setPlaybackError] = useState<string | null>(null);
  const [currentSentenceIndex, setCurrentSentenceIndex] = useState<number | null>(null);
  const [currentRepeatIndex, setCurrentRepeatIndex] = useState<number | null>(null);
  const [cycleIndex, setCycleIndex] = useState<number | null>(null);

  const runIdRef = useRef(0);
  const stopRef = useRef(false);
  const playerRef = useRef<AudioPlayer | null>(null);
  const pendingFetchRef = useRef<AbortController | null>(null);

  const wordsCount = useMemo(() => countWords(activeText), [activeText]);
  const sentences = useMemo(() => splitIntoSentences(activeText), [activeText]);
  const hasActiveText = useMemo(() => activeText.trim().length > 0, [activeText]);

  const languageLabel = useMemo(() => {
    const found = LANGUAGE_OPTIONS.find((option) => option.code === selectedLanguage);
    return found ? found.label : selectedLanguage;
  }, [selectedLanguage]);

  const combinedInstructions = useMemo(() => {
    const base = languageLabel ? `Speak in ${languageLabel}.` : '';
    const extra = instructionsInput.trim();
    if (base && extra) return `${base} ${extra}`;
    return base || extra;
  }, [instructionsInput, languageLabel]);

  const serverBaseUrl = useMemo(() => serverUrl.trim().replace(/\/+$/, ''), [serverUrl]);

  useEffect(() => {
    setAudioModeAsync({
      playsInSilentMode: true,
      interruptionMode: 'duckOthers',
      allowsRecording: false,
      shouldPlayInBackground: false,
      shouldRouteThroughEarpiece: false,
    }).catch(() => {
      // Ignore audio mode errors
    });
  }, []);

  useEffect(() => {
    return () => {
      pendingFetchRef.current?.abort();
      if (playerRef.current) {
        playerRef.current.pause();
        playerRef.current.remove();
        playerRef.current = null;
      }
    };
  }, []);

  const stopPlayback = useCallback(async () => {
    stopRef.current = true;
    runIdRef.current += 1;
    setIsPlaying(false);
    setIsPaused(false);
    setIsFetchingAudio(false);
    setPlaybackError(null);
    setCurrentSentenceIndex(null);
    setCurrentRepeatIndex(null);
    setCycleIndex(null);
    try {
      pendingFetchRef.current?.abort();
      pendingFetchRef.current = null;
      if (playerRef.current) {
        playerRef.current.pause();
        playerRef.current.remove();
        playerRef.current = null;
      }
    } catch {
      // Ignore stop failures
    }
  }, []);

  const fetchAudioFile = useCallback(
    async (text: string) => {
      if (!serverBaseUrl) {
        throw new Error('Server URL is required.');
      }
      const speed = clamp(parseFloatSafe(rateInput, DEFAULT_RATE), 0.25, 4.0);
      const model = ttsModel.trim() || DEFAULT_TTS_MODEL;
      const voice = selectedVoiceId || DEFAULT_TTS_VOICE;
      const payload = {
        text,
        voice,
        model,
        format: DEFAULT_TTS_FORMAT,
        speed,
        instructions: combinedInstructions,
        language: selectedLanguage,
      };
      const cacheKey = simpleHash(JSON.stringify(payload));
      const baseDir = FileSystem.cacheDirectory ?? FileSystem.documentDirectory;
      if (!baseDir) {
        throw new Error('File system is unavailable on this platform.');
      }
      const fileDir = `${baseDir}diktat-tts`;
      const fileUri = `${fileDir}/${cacheKey}.${DEFAULT_TTS_FORMAT}`;

      const info = await FileSystem.getInfoAsync(fileUri);
      if (info.exists) return fileUri;

      setIsFetchingAudio(true);
      const controller = new AbortController();
      pendingFetchRef.current = controller;

      try {
        const response = await fetch(`${serverBaseUrl}/tts`, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            ...(serverAuthToken ? { Authorization: `Bearer ${serverAuthToken}` } : {}),
          },
          body: JSON.stringify(payload),
          signal: controller.signal,
        });

        if (!response.ok) {
          const message = await response.text();
          throw new Error(message || 'Server error');
        }

        const buffer = await response.arrayBuffer();
        const base64 = arrayBufferToBase64(buffer);

        await FileSystem.makeDirectoryAsync(fileDir, { intermediates: true });
        await FileSystem.writeAsStringAsync(fileUri, base64, {
          encoding: FileSystem.EncodingType.Base64,
        });
        return fileUri;
      } finally {
        setIsFetchingAudio(false);
        pendingFetchRef.current = null;
      }
    },
    [
      combinedInstructions,
      rateInput,
      selectedLanguage,
      selectedVoiceId,
      serverAuthToken,
      serverBaseUrl,
      ttsModel,
    ]
  );

  const playAudioFile = useCallback(async (fileUri: string) => {
    if (stopRef.current) return;

    let player = playerRef.current;
    if (!player) {
      player = createAudioPlayer({ uri: fileUri }, { updateInterval: 250 });
      playerRef.current = player;
    } else {
      player.replace({ uri: fileUri });
    }

    setIsPaused(false);

    await new Promise<void>((resolve) => {
      let finished = false;
      let interval: ReturnType<typeof setInterval> | null = null;
      const cleanup = () => {
        if (interval) {
          clearInterval(interval);
        }
      };
      const subscription = player.addListener('playbackStatusUpdate', (status: AudioStatus) => {
        if (status.didJustFinish && !finished) {
          finished = true;
          subscription.remove();
          cleanup();
          resolve();
        }
      });

      player.play();

      interval = setInterval(() => {
        if (stopRef.current && !finished) {
          finished = true;
          subscription.remove();
          try {
            player.pause();
          } catch {
            // Ignore pause failures
          }
          cleanup();
          resolve();
        }
      }, 200);
    });
  }, []);

  const speakChunks = useCallback(
    async (text: string) => {
      const maxLength = 2000;
      const chunks = chunkText(text, maxLength);
      for (const chunk of chunks) {
        if (stopRef.current) return;
        const fileUri = await fetchAudioFile(chunk);
        if (stopRef.current) return;
        await playAudioFile(fileUri);
      }
    },
    [fetchAudioFile, playAudioFile]
  );

  const runFullDiktat = useCallback(async () => {
    if (!activeText.trim()) return;
    stopRef.current = false;
    setPlaybackError(null);
    const runId = runIdRef.current + 1;
    runIdRef.current = runId;
    setIsPlaying(true);
    setIsPaused(false);
    setCurrentSentenceIndex(null);
    setCurrentRepeatIndex(null);

    const loops = parsePositiveInt(loopCountInput, DEFAULT_LOOP_COUNT);
    const gapSeconds = parseFloatSafe(gapSecondsInput, DEFAULT_GAP_SECONDS);
    const totalLoops = loops <= 0 ? Number.POSITIVE_INFINITY : loops;

    try {
      for (let loop = 0; loop < totalLoops; loop += 1) {
        if (stopRef.current || runId !== runIdRef.current) break;
        setCycleIndex(loop + 1);
        await speakChunks(activeText);
        if (stopRef.current || runId !== runIdRef.current) break;
        if (gapSeconds > 0) {
          await sleep(gapSeconds * 1000);
        }
      }
    } catch (error) {
      if (!stopRef.current) {
        const message = error instanceof Error ? error.message : 'Playback failed.';
        setPlaybackError(message);
      }
    } finally {
      setIsPlaying(false);
      setIsPaused(false);
      setIsFetchingAudio(false);
    }
  }, [activeText, gapSecondsInput, loopCountInput, speakChunks]);

  const runSentenceMode = useCallback(async () => {
    if (!activeText.trim()) return;
    stopRef.current = false;
    setPlaybackError(null);
    const runId = runIdRef.current + 1;
    runIdRef.current = runId;
    setIsPlaying(true);
    setIsPaused(false);
    setCycleIndex(null);

    const repeats = Math.max(1, parsePositiveInt(repeatCountInput, DEFAULT_REPEAT_COUNT));
    const gapSeconds = parseFloatSafe(gapSecondsInput, DEFAULT_GAP_SECONDS);

    try {
      for (let index = 0; index < sentences.length; index += 1) {
        if (stopRef.current || runId !== runIdRef.current) break;
        setCurrentSentenceIndex(index);
        const sentence = sentences[index];
        for (let repeat = 0; repeat < repeats; repeat += 1) {
          if (stopRef.current || runId !== runIdRef.current) break;
          setCurrentRepeatIndex(repeat + 1);
          await speakChunks(sentence);
          if (gapSeconds > 0) {
            await sleep(gapSeconds * 1000);
          }
        }
      }
    } catch (error) {
      if (!stopRef.current) {
        const message = error instanceof Error ? error.message : 'Playback failed.';
        setPlaybackError(message);
      }
    } finally {
      setIsPlaying(false);
      setIsPaused(false);
      setIsFetchingAudio(false);
    }
  }, [activeText, gapSecondsInput, repeatCountInput, sentences, speakChunks]);

  const handleStart = useCallback(() => {
    if (isPlaying) return;
    if (!activeText.trim()) return;
    if (mode === 'full') {
      runFullDiktat();
    } else {
      runSentenceMode();
    }
  }, [activeText, isPlaying, mode, runFullDiktat, runSentenceMode]);

  const handleTogglePlayPause = useCallback(async () => {
    if (!hasActiveText) return;
    if (!isPlaying) {
      setIsPaused(false);
      handleStart();
      return;
    }

    if (isPaused) {
      setIsPaused(false);
      try {
        playerRef.current?.play();
      } catch {
        // Ignore resume failures
      }
      return;
    }

    setIsPaused(true);
    try {
      playerRef.current?.pause();
    } catch {
      // Ignore pause failures
    }
  }, [handleStart, hasActiveText, isPaused, isPlaying]);

  const handleUseDraft = useCallback(() => {
    const normalized = normalizeWhitespace(draftText);
    setActiveText(normalized);
  }, [draftText]);

  const handleFetchUrl = useCallback(async () => {
    const trimmed = urlInput.trim();
    if (!trimmed) return;
    setFetchState('loading');
    setFetchError(null);
    const url = /^https?:\/\//i.test(trimmed) ? trimmed : `https://${trimmed}`;

    try {
      const response = await fetch(url);
      const contentType = response.headers.get('content-type') ?? '';
      const body = await response.text();
      const extracted = contentType.includes('text/html') ? extractTextFromHtml(body) : normalizeWhitespace(body);
      setDraftText(extracted);
      setFetchState('idle');
    } catch (error) {
      setFetchError('Unable to fetch that URL. Try pasting the text directly.');
      setFetchState('error');
    }
  }, [urlInput]);

  const currentSentence =
    currentSentenceIndex != null && currentSentenceIndex >= 0 && currentSentenceIndex < sentences.length
      ? sentences[currentSentenceIndex]
      : null;

  const repeatTarget = useMemo(
    () => Math.max(1, parsePositiveInt(repeatCountInput, DEFAULT_REPEAT_COUNT)),
    [repeatCountInput]
  );

  const statusLine = useMemo(() => {
    if (!hasActiveText) return 'Load a text to start practicing.';
    if (playbackError) return `Error: ${playbackError}`;
    if (isFetchingAudio) return 'Fetching audio...';
    if (isPaused) return 'Paused.';
    if (mode === 'full') {
      return isPlaying ? `Full diktat - Cycle ${cycleIndex ?? 0}` : 'Full diktat ready.';
    }
    const sentenceValue = currentSentenceIndex != null ? currentSentenceIndex + 1 : 0;
    if (isPlaying) {
      return `Sentence repeat - ${sentenceValue}/${sentences.length} | Repeat ${
        currentRepeatIndex ?? 0
      }/${repeatTarget}`;
    }
    return `Sentence repeat - ${sentences.length} sentences.`;
  }, [
    cycleIndex,
    currentRepeatIndex,
    currentSentenceIndex,
    hasActiveText,
    isFetchingAudio,
    isPlaying,
    isPaused,
    mode,
    playbackError,
    repeatTarget,
    sentences.length,
  ]);

  return (
    <SafeAreaView style={styles.safeArea} edges={['top', 'bottom']}>
      <StatusBar style="dark" />
      <KeyboardAvoidingView
        style={styles.container}
        behavior={Platform.OS === 'ios' ? 'padding' : undefined}
      >
        <ScrollView
          contentContainerStyle={[styles.scrollContent, { paddingBottom: 160 + insets.bottom }]}
          keyboardShouldPersistTaps="handled"
        >
          <View style={styles.header}>
            <Text style={styles.title}>Diktat</Text>
            <Text style={styles.subtitle}>Write, listen, shadow. Build accuracy one loop at a time.</Text>
          </View>

          <View style={styles.section}>
            <Text style={styles.sectionTitle}>Text source</Text>
            <Text style={styles.sectionHint}>
              Paste text or fetch a page. For best results, paste clean text.
            </Text>
            <View style={styles.row}>
              <TextInput
                value={urlInput}
                onChangeText={setUrlInput}
                placeholder="https://example.com/article"
                placeholderTextColor={colors.muted}
                style={[styles.input, styles.inputInline]}
                autoCapitalize="none"
                autoCorrect={false}
              />
              <Pressable
                style={[styles.button, styles.buttonOutline, styles.buttonInline]}
                onPress={handleFetchUrl}
                disabled={fetchState === 'loading'}
              >
                {fetchState === 'loading' ? (
                  <ActivityIndicator color={colors.text} />
                ) : (
                  <Text style={styles.buttonText}>Fetch</Text>
                )}
              </Pressable>
            </View>
            {fetchError ? <Text style={styles.errorText}>{fetchError}</Text> : null}
            <TextInput
              value={draftText}
              onChangeText={setDraftText}
              placeholder="Paste or edit text here"
              placeholderTextColor={colors.muted}
              style={[styles.input, styles.textArea]}
              multiline
              textAlignVertical="top"
            />
            <Pressable style={[styles.button, styles.buttonPrimary]} onPress={handleUseDraft}>
              <Text style={styles.buttonTextPrimary}>Use this text</Text>
            </Pressable>
          </View>

          <View style={styles.section}>
            <Text style={styles.sectionTitle}>Active text</Text>
            <View style={styles.statsRow}>
              <View style={styles.statCard}>
                <Text style={styles.statValue}>{wordsCount}</Text>
                <Text style={styles.statLabel}>Words</Text>
              </View>
              <View style={styles.statCard}>
                <Text style={styles.statValue}>{sentences.length}</Text>
                <Text style={styles.statLabel}>Sentences</Text>
              </View>
            </View>
            <Text style={styles.previewText} numberOfLines={5}>
              {activeText ? activeText : 'No text loaded yet.'}
            </Text>
          </View>

          <View style={styles.section}>
            <Text style={styles.sectionTitle}>Write</Text>
            <Text style={styles.sectionHint}>Type what you hear while the player runs.</Text>
            <TextInput
              value={attemptText}
              onChangeText={setAttemptText}
              placeholder="Write what you hear here"
              placeholderTextColor={colors.muted}
              style={[styles.input, styles.textArea]}
              multiline
              textAlignVertical="top"
            />
          </View>
        </ScrollView>
      </KeyboardAvoidingView>
      <View style={[styles.bottomBarWrapper, { paddingBottom: 16 + insets.bottom }]}>
        <View style={[styles.bottomBar, !hasActiveText && styles.bottomBarDisabled]}>
          <View style={styles.bottomBarInfo}>
            <Text style={styles.bottomBarTitle}>Practice</Text>
              <View style={styles.bottomBarStatusRow}>
                {isFetchingAudio ? <ActivityIndicator size="small" color={colors.text} /> : null}
                <Text style={styles.bottomBarSubtitle} numberOfLines={1}>
                  {statusLine}
                </Text>
              </View>
            </View>
          <View style={styles.bottomBarControls}>
            <Pressable
              style={[styles.bottomBarButton, styles.bottomBarPrimary]}
              onPress={handleTogglePlayPause}
              disabled={!hasActiveText}
            >
              <Text style={styles.bottomBarButtonText}>
                {isPlaying ? (isPaused ? 'Resume' : 'Pause') : 'Play'}
              </Text>
            </Pressable>
            <Pressable
              style={[styles.bottomBarButton, styles.bottomBarOutline]}
              onPress={() => setIsPracticeExpanded(true)}
              disabled={!hasActiveText}
            >
              <Text style={[styles.bottomBarButtonText, styles.bottomBarButtonTextOutline]}>Details</Text>
            </Pressable>
          </View>
        </View>
      </View>
      <Modal
        visible={isPracticeExpanded}
        animationType="slide"
        onRequestClose={() => setIsPracticeExpanded(false)}
      >
        <SafeAreaView style={styles.modalContainer} edges={['top', 'bottom']}>
          <View style={styles.modalHeader}>
            <View>
              <Text style={styles.modalTitle}>Practice</Text>
              <Text style={styles.sectionHint}>{statusLine}</Text>
            </View>
            <Pressable
              style={[styles.button, styles.buttonOutline, styles.modalCloseButton]}
              onPress={() => setIsPracticeExpanded(false)}
            >
              <Text style={styles.buttonText}>Close</Text>
            </Pressable>
          </View>
          {playbackError ? (
            <View style={styles.modalError}>
              <Text style={styles.errorText}>{playbackError}</Text>
            </View>
          ) : null}

          <ScrollView contentContainerStyle={styles.modalContent}>
            <View style={styles.section}>
              <Text style={styles.sectionTitle}>Playback</Text>
              <View style={styles.row}>
                <Pressable
                  style={[styles.button, styles.buttonPrimary, styles.buttonInline]}
                  onPress={handleTogglePlayPause}
                  disabled={!hasActiveText}
                >
                  <Text style={styles.buttonTextPrimary}>
                    {isPlaying ? (isPaused ? 'Resume' : 'Pause') : 'Play'}
                  </Text>
                </Pressable>
                <Pressable
                  style={[styles.button, styles.buttonOutline, styles.buttonInline]}
                  onPress={stopPlayback}
                  disabled={!isPlaying}
                >
                  <Text style={styles.buttonText}>Stop</Text>
                </Pressable>
              </View>

              {mode === 'full' ? (
                <View style={styles.statusCard}>
                  <Text style={styles.statusLabel}>Cycle</Text>
                  <Text style={styles.statusValue}>{cycleIndex ?? 0}</Text>
                </View>
              ) : (
                <View style={styles.statusCard}>
                  <Text style={styles.statusLabel}>Sentence</Text>
                  <Text style={styles.statusValue}>
                    {currentSentenceIndex != null ? currentSentenceIndex + 1 : 0}/{sentences.length}
                  </Text>
                  <Text style={styles.statusSubValue}>
                    Repeat {currentRepeatIndex ?? 0}/{repeatTarget}
                  </Text>
                  {currentSentence ? (
                    <Text style={styles.currentSentence} numberOfLines={3}>
                      "{currentSentence}"
                    </Text>
                  ) : null}
                </View>
              )}
            </View>

            <View style={styles.section}>
              <Text style={styles.sectionTitle}>Mode</Text>
              <View style={styles.segmentedControl}>
                <Pressable
                  style={[styles.segment, mode === 'full' && styles.segmentActive]}
                  onPress={() => setMode('full')}
                >
                  <Text style={[styles.segmentText, mode === 'full' && styles.segmentTextActive]}>
                    Full diktat
                  </Text>
                </Pressable>
                <Pressable
                  style={[styles.segment, mode === 'sentence' && styles.segmentActive]}
                  onPress={() => setMode('sentence')}
                >
                  <Text style={[styles.segmentText, mode === 'sentence' && styles.segmentTextActive]}>
                    Sentence repeat
                  </Text>
                </Pressable>
              </View>
              <Text style={styles.sectionHint}>
                Full diktat replays the entire text from the start each time. Sentence repeat walks the text sentence by
                sentence.
              </Text>
            </View>

            <View style={styles.section}>
              <Text style={styles.sectionTitle}>Speech controls</Text>
              <View style={styles.controlRow}>
                <View style={styles.controlItem}>
                  <Text style={styles.controlLabel}>Rate</Text>
                  <TextInput
                    value={rateInput}
                    onChangeText={setRateInput}
                    keyboardType="decimal-pad"
                    style={styles.input}
                  />
                </View>
                <View style={styles.controlItem}>
                  <Text style={styles.controlLabel}>Gap (sec)</Text>
                  <TextInput
                    value={gapSecondsInput}
                    onChangeText={setGapSecondsInput}
                    keyboardType="decimal-pad"
                    style={styles.input}
                  />
                </View>
                {mode === 'sentence' ? (
                  <View style={styles.controlItem}>
                    <Text style={styles.controlLabel}>Repeats</Text>
                    <TextInput
                      value={repeatCountInput}
                      onChangeText={setRepeatCountInput}
                      keyboardType="number-pad"
                      style={styles.input}
                    />
                  </View>
                ) : (
                  <View style={styles.controlItem}>
                    <Text style={styles.controlLabel}>Loops (0=inf)</Text>
                    <TextInput
                      value={loopCountInput}
                      onChangeText={setLoopCountInput}
                      keyboardType="number-pad"
                      style={styles.input}
                    />
                  </View>
                )}
              </View>
              <Text style={styles.sectionHint}>Tip: use a slower rate for accuracy drills.</Text>
            </View>

            <View style={styles.section}>
              <Text style={styles.sectionTitle}>Server</Text>
              <Text style={styles.sectionHint}>
                Use your LAN IP when testing on a real device (for example, http://192.168.1.10:8787).
              </Text>
              <TextInput
                value={serverUrl}
                onChangeText={setServerUrl}
                placeholder="http://localhost:8787"
                placeholderTextColor={colors.muted}
                style={[styles.input, styles.inputSpacer]}
                autoCapitalize="none"
                autoCorrect={false}
              />
              <TextInput
                value={serverAuthToken}
                onChangeText={setServerAuthToken}
                placeholder="Optional auth token"
                placeholderTextColor={colors.muted}
                style={[styles.input, styles.inputSpacer]}
                autoCapitalize="none"
                autoCorrect={false}
                secureTextEntry
              />
              <TextInput
                value={ttsModel}
                onChangeText={setTtsModel}
                placeholder="Model (gpt-4o-mini-tts, tts-1, tts-1-hd)"
                placeholderTextColor={colors.muted}
                style={[styles.input, styles.inputSpacer]}
                autoCapitalize="none"
                autoCorrect={false}
              />
              <TextInput
                value={instructionsInput}
                onChangeText={setInstructionsInput}
                placeholder="Extra voice instructions (optional)"
                placeholderTextColor={colors.muted}
                style={[styles.input, styles.textArea, styles.inputSpacer]}
                multiline
                textAlignVertical="top"
              />
            </View>

            <View style={styles.section}>
              <Text style={styles.sectionTitle}>Voice</Text>
              <Text style={styles.sectionHint}>
                Select a language and an OpenAI voice. Voices are currently optimized for English.
              </Text>
              <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={styles.voiceRow}>
                {LANGUAGE_OPTIONS.map((option) => {
                  const isSelected = option.code === selectedLanguage;
                  return (
                    <Pressable
                      key={option.code}
                      style={[styles.voiceChip, isSelected && styles.voiceChipActive]}
                      onPress={() => setSelectedLanguage(option.code)}
                    >
                      <Text style={[styles.voiceName, isSelected && styles.voiceNameActive]} numberOfLines={1}>
                        {option.label}
                      </Text>
                      <Text style={[styles.voiceMeta, isSelected && styles.voiceNameActive]} numberOfLines={1}>
                        {option.code}
                      </Text>
                    </Pressable>
                  );
                })}
              </ScrollView>
              <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={styles.voiceRow}>
                {OPENAI_VOICES.map((voice) => {
                  const isSelected = voice.id === selectedVoiceId;
                  return (
                    <Pressable
                      key={voice.id}
                      style={[styles.voiceChip, isSelected && styles.voiceChipActive]}
                      onPress={() => setSelectedVoiceId(voice.id)}
                    >
                      <Text style={[styles.voiceName, isSelected && styles.voiceNameActive]} numberOfLines={1}>
                        {voice.label}
                      </Text>
                      <Text style={[styles.voiceMeta, isSelected && styles.voiceNameActive]} numberOfLines={1}>
                        {voice.id}
                      </Text>
                    </Pressable>
                  );
                })}
              </ScrollView>
            </View>
          </ScrollView>
        </SafeAreaView>
      </Modal>
    </SafeAreaView>
  );
}

export default function App() {
  return (
    <SafeAreaProvider>
      <AppContent />
    </SafeAreaProvider>
  );
}

const colors = {
  background: '#f6f1ea',
  card: '#ffffff',
  text: '#1f1b16',
  muted: '#7a6f66',
  border: '#e6ded2',
  accent: '#2e5c50',
  accentSoft: '#d7e6e0',
};

const styles = StyleSheet.create({
  safeArea: {
    flex: 1,
    backgroundColor: colors.background,
  },
  container: {
    flex: 1,
  },
  scrollContent: {
    padding: 20,
    paddingBottom: 160,
  },
  header: {
    marginBottom: 24,
  },
  title: {
    fontSize: 32,
    fontWeight: '700',
    color: colors.text,
  },
  subtitle: {
    marginTop: 6,
    fontSize: 16,
    color: colors.muted,
  },
  section: {
    backgroundColor: colors.card,
    borderRadius: 18,
    padding: 16,
    marginBottom: 18,
    borderWidth: 1,
    borderColor: colors.border,
  },
  sectionTitle: {
    fontSize: 18,
    fontWeight: '600',
    color: colors.text,
  },
  sectionHint: {
    marginTop: 6,
    color: colors.muted,
    fontSize: 13,
  },
  row: {
    flexDirection: 'row',
    gap: 12,
    marginTop: 12,
  },
  input: {
    borderWidth: 1,
    borderColor: colors.border,
    borderRadius: 12,
    paddingHorizontal: 12,
    paddingVertical: 10,
    fontSize: 14,
    color: colors.text,
    backgroundColor: '#fffdf9',
  },
  inputInline: {
    flex: 1,
  },
  button: {
    borderRadius: 12,
    paddingVertical: 12,
    paddingHorizontal: 16,
    alignItems: 'center',
    justifyContent: 'center',
    minWidth: 96,
  },
  buttonInline: {
    minWidth: 110,
  },
  buttonPrimary: {
    backgroundColor: colors.accent,
  },
  buttonOutline: {
    borderWidth: 1,
    borderColor: colors.text,
  },
  buttonText: {
    color: colors.text,
    fontWeight: '600',
  },
  buttonTextPrimary: {
    color: '#fff',
    fontWeight: '600',
  },
  textArea: {
    minHeight: 120,
    marginTop: 12,
  },
  inputSpacer: {
    marginTop: 12,
  },
  statsRow: {
    flexDirection: 'row',
    gap: 12,
    marginTop: 12,
  },
  statCard: {
    flex: 1,
    backgroundColor: colors.accentSoft,
    padding: 12,
    borderRadius: 12,
  },
  statValue: {
    fontSize: 20,
    fontWeight: '700',
    color: colors.accent,
  },
  statLabel: {
    fontSize: 12,
    color: colors.muted,
  },
  previewText: {
    marginTop: 12,
    fontSize: 14,
    color: colors.text,
  },
  segmentedControl: {
    flexDirection: 'row',
    backgroundColor: '#f2ece3',
    borderRadius: 14,
    padding: 4,
    marginTop: 12,
  },
  segment: {
    flex: 1,
    paddingVertical: 10,
    borderRadius: 12,
    alignItems: 'center',
  },
  segmentActive: {
    backgroundColor: colors.card,
    borderWidth: 1,
    borderColor: colors.border,
  },
  segmentText: {
    color: colors.muted,
    fontWeight: '600',
  },
  segmentTextActive: {
    color: colors.text,
  },
  controlRow: {
    flexDirection: 'row',
    gap: 12,
    marginTop: 12,
  },
  controlItem: {
    flex: 1,
  },
  controlLabel: {
    fontSize: 12,
    color: colors.muted,
    marginBottom: 6,
  },
  voiceRow: {
    gap: 10,
    paddingVertical: 12,
  },
  voiceChip: {
    paddingVertical: 10,
    paddingHorizontal: 12,
    borderRadius: 14,
    borderWidth: 1,
    borderColor: colors.border,
    minWidth: 140,
    backgroundColor: '#fffdf9',
  },
  voiceChipActive: {
    backgroundColor: colors.accent,
    borderColor: colors.accent,
  },
  voiceName: {
    fontSize: 13,
    fontWeight: '600',
    color: colors.text,
  },
  voiceMeta: {
    fontSize: 11,
    color: colors.muted,
    marginTop: 4,
  },
  voiceNameActive: {
    color: '#fff',
  },
  statusCard: {
    marginTop: 12,
    padding: 12,
    borderRadius: 12,
    backgroundColor: '#fffdf9',
    borderWidth: 1,
    borderColor: colors.border,
  },
  statusLabel: {
    color: colors.muted,
    fontSize: 12,
  },
  statusValue: {
    fontSize: 22,
    fontWeight: '700',
    color: colors.text,
  },
  statusSubValue: {
    color: colors.muted,
    marginTop: 2,
  },
  currentSentence: {
    marginTop: 10,
    color: colors.text,
    fontStyle: 'italic',
  },
  errorText: {
    marginTop: 8,
    color: '#9c2d2d',
  },
  bottomBarWrapper: {
    position: 'absolute',
    left: 0,
    right: 0,
    bottom: 0,
    paddingHorizontal: 16,
    paddingBottom: 16,
  },
  bottomBar: {
    backgroundColor: colors.card,
    borderRadius: 18,
    borderWidth: 1,
    borderColor: colors.border,
    padding: 14,
    flexDirection: 'row',
    alignItems: 'center',
    gap: 12,
  },
  bottomBarDisabled: {
    opacity: 0.5,
  },
  bottomBarInfo: {
    flex: 1,
  },
  bottomBarTitle: {
    fontSize: 14,
    fontWeight: '700',
    color: colors.text,
  },
  bottomBarSubtitle: {
    fontSize: 12,
    color: colors.muted,
    flexShrink: 1,
  },
  bottomBarStatusRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
    marginTop: 4,
  },
  bottomBarControls: {
    flexDirection: 'row',
    gap: 8,
  },
  bottomBarButton: {
    borderRadius: 12,
    paddingVertical: 10,
    paddingHorizontal: 12,
    alignItems: 'center',
    justifyContent: 'center',
    minWidth: 72,
  },
  bottomBarPrimary: {
    backgroundColor: colors.accent,
  },
  bottomBarOutline: {
    borderWidth: 1,
    borderColor: colors.text,
  },
  bottomBarButtonText: {
    color: '#fff',
    fontWeight: '600',
  },
  bottomBarButtonTextOutline: {
    color: colors.text,
  },
  modalContainer: {
    flex: 1,
    backgroundColor: colors.background,
  },
  modalHeader: {
    paddingHorizontal: 20,
    paddingTop: 12,
    paddingBottom: 8,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    gap: 12,
  },
  modalTitle: {
    fontSize: 22,
    fontWeight: '700',
    color: colors.text,
  },
  modalContent: {
    padding: 20,
    paddingBottom: 40,
  },
  modalCloseButton: {
    minWidth: 80,
  },
  modalError: {
    paddingHorizontal: 20,
    paddingBottom: 8,
  },
});
