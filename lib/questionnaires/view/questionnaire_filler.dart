import 'package:fhir/r4/r4.dart';
import 'package:flutter/material.dart';

import '../../logging/logging.dart';
import '../../resource_provider/resource_provider.dart';
import '../questionnaires.dart';

/// Fill a [Questionnaire].
///
/// Provides visual components to view and fill a [Questionnaire].
/// The components are provided as a [List] of [Widget]s of type [QuestionnaireItemFiller].
/// It is up to a higher-level component to present these to the user.
///
/// see: [QuestionnaireScrollerPage]
/// see: [QuestionnaireStepperPage]
class QuestionnaireFiller extends StatefulWidget {
  final Locale locale;
  final WidgetBuilder builder;
  final List<Aggregator<dynamic>>? aggregators;
  final void Function(BuildContext context, Uri url)? onLinkTap;

  final FhirResourceProvider fhirResourceProvider;

  Future<QuestionnaireTopLocation> _createTopLocation() async =>
      QuestionnaireTopLocation.fromFhirResourceBundle(
          locale: locale,
          aggregators: aggregators,
          fhirResourceProvider: fhirResourceProvider);

  const QuestionnaireFiller(
      {Key? key,
      required this.locale,
      required this.builder,
      required this.fhirResourceProvider,
      this.aggregators,
      this.onLinkTap})
      : super(key: key);

  static QuestionnaireFillerData of(BuildContext context) {
    final result =
        context.dependOnInheritedWidgetOfExactType<QuestionnaireFillerData>();
    assert(result != null, 'No QuestionnaireFillerData found in context');
    return result!;
  }

  @override
  _QuestionnaireFillerState createState() => _QuestionnaireFillerState();
}

class _QuestionnaireFillerState extends State<QuestionnaireFiller> {
  static final logger = Logger(_QuestionnaireFillerState);

  late final Future<QuestionnaireTopLocation> builderFuture;
  QuestionnaireTopLocation? _topLocation;
  void Function()? _onTopChangeListenerFunction;

  @override
  void initState() {
    super.initState();
    builderFuture = widget._createTopLocation();
  }

  @override
  void dispose() {
    logger.trace('dispose');

    if (_onTopChangeListenerFunction != null && _topLocation != null) {
      _topLocation!.removeListener(_onTopChangeListenerFunction!);
      _topLocation = null;
      _onTopChangeListenerFunction = null;
    }
    super.dispose();
  }

  void _onTopChange() {
    logger.trace('_onTopChange');
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    logger.trace('Enter build()');
    return FutureBuilder<QuestionnaireTopLocation>(
        future: builderFuture,
        builder: (context, snapshot) {
          switch (snapshot.connectionState) {
            case ConnectionState.active:
              // This should never happen in our use-case (is for streaming)
              logger.warn('FutureBuilder is active...');
              return QuestionnaireLoadingIndicator(snapshot);
            case ConnectionState.none:
              return QuestionnaireLoadingIndicator(snapshot);
            case ConnectionState.waiting:
              logger.log('FutureBuilder still waiting for data...',
                  level: LogLevel.debug);
              return QuestionnaireLoadingIndicator(snapshot);
            case ConnectionState.done:
              if (snapshot.hasError) {
                logger.warn('FutureBuilder hasError');
                return QuestionnaireLoadingIndicator(snapshot);
              }
              if (snapshot.hasData) {
                logger.log('FutureBuilder hasData');
                _topLocation = snapshot.data;
                // TODO: There has got to be a more elegant way! Goal is to register the lister exactly once, after the future has completed.
                // Dart has abilities to chain Futures.
                if (_onTopChangeListenerFunction == null) {
                  _onTopChangeListenerFunction = () => _onTopChange();
                  _topLocation!.addListener(_onTopChangeListenerFunction!);
                }
                return QuestionnaireFillerData._(
                  _topLocation!,
                  locale: widget.locale,
                  builder: widget.builder,
                  onLinkTap: widget.onLinkTap,
                );
              }
              throw StateError(
                  'FutureBuilder snapshot has unexpected state: $snapshot');
          }
        });
  }
}

class QuestionnaireFillerData extends InheritedWidget {
  static final logger = Logger(QuestionnaireFillerData);
  final Locale locale;
  final QuestionnaireTopLocation topLocation;
  final Iterable<QuestionnaireLocation> surveyLocations;
  final void Function(BuildContext context, Uri url)? onLinkTap;
  late final List<QuestionnaireItemFiller?> _itemFillers;
  late final int _revision;

  QuestionnaireFillerData._(
    this.topLocation, {
    Key? key,
    required this.locale,
    this.onLinkTap,
    required WidgetBuilder builder,
  })  : _revision = topLocation.revision,
        surveyLocations = topLocation.preOrder(),
        _itemFillers = List<QuestionnaireItemFiller?>.filled(
            topLocation.preOrder().length, null),
        super(key: key, child: Builder(builder: builder));

  T aggregator<T extends Aggregator>() {
    return topLocation.aggregator<T>();
  }

  static QuestionnaireFillerData of(BuildContext context) {
    final result =
        context.dependOnInheritedWidgetOfExactType<QuestionnaireFillerData>();
    assert(result != null, 'No QuestionnaireFillerData found in context');
    return result!;
  }

  List<QuestionnaireItemFiller> itemFillers() {
    for (int i = 0; i < _itemFillers.length; i++) {
      if (_itemFillers[i] == null) {
        _itemFillers[i] = itemFillerAt(i);
      }
    }

    return _itemFillers
        .map<QuestionnaireItemFiller>(
            (itemFiller) => ArgumentError.checkNotNull(itemFiller))
        .toList();
  }

  QuestionnaireItemFiller itemFillerAt(int index) {
    _itemFillers[index] ??= QuestionnaireItemFiller.fromQuestionnaireItem(
        surveyLocations.elementAt(index));

    return _itemFillers[index]!;
  }

  @override
  bool updateShouldNotify(QuestionnaireFillerData oldWidget) {
    return oldWidget._revision != _revision;
  }
}
