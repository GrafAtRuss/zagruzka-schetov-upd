
#Область ПрограммныйИнтерфейс

// Сбрасывает сохраненную панель разделов один раз, чтобы появился раздел загрузки.
// Возвращает Истина, если интерфейс нужно обновить.
Функция ПоказатьРаздел() Экспорт

	Если Не ПравоДоступа("Просмотр", Метаданные.Подсистемы.ЗС_ЗагрузкаДокументов) Тогда
		Возврат Ложь;
	КонецЕсли;

	КлючФлага = "ЗС/РазделВПанели";
	Попытка
		Если ХранилищеСистемныхНастроек.Загрузить(КлючФлага) = Истина Тогда
			Возврат Ложь;
		КонецЕсли;
		ХранилищеСистемныхНастроек.Удалить("Общее/ПанельРазделов/НастройкиКомандногоИнтерфейса");
		ХранилищеСистемныхНастроек.Сохранить(КлючФлага, "", Истина);
	Исключение
		Возврат Ложь;
	КонецПопытки;

	Возврат Истина;

КонецФункции

// Возвращает JSON с реквизитами счета или УПД либо с полем Ошибка.
Функция РазобратьPDF(ДвоичныеДанные) Экспорт

	Если ТипЗнч(ДвоичныеДанные) <> Тип("ДвоичныеДанные") Тогда
		Возврат "{""Ошибка"":""Не переданы данные файла.""}";
	КонецЕсли;

	Возврат ИзвлечьJSON(ДвоичныеДанные);

КонецФункции

// Создает счет покупателю и/или УПД (реализация услуг + счет-фактура).
// Возвращает текст протокола.
Функция СоздатьДокументы(СтрокаJSON) Экспорт

	Чтение = Новый ЧтениеJSON;
	Чтение.УстановитьСтроку(СтрокаJSON);
	Данные = ПрочитатьJSON(Чтение);

	Если ТипЗнч(Данные) <> Тип("Структура") Тогда
		ВызватьИсключение "Некорректные данные распознавания.";
	КонецЕсли;
	Если Данные.Свойство("Ошибка") И ЗначениеЗаполнено(Данные.Ошибка) Тогда
		ВызватьИсключение Данные.Ошибка;
	КонецЕсли;

	СоздаватьСчет = Истина;
	СоздаватьУПД = Истина;
	Если Данные.Свойство("СоздатьСчет") Тогда
		СоздаватьСчет = Данные.СоздатьСчет;
	КонецЕсли;
	Если Данные.Свойство("СоздатьУПД") Тогда
		СоздаватьУПД = Данные.СоздатьУПД;
	КонецЕсли;
	Если Не СоздаватьСчет И Не СоздаватьУПД Тогда
		ВызватьИсключение "Отметьте счет, УПД или оба документа.";
	КонецЕсли;

	ДатаДок = ДатаИзСтроки(Данные.Дата);
	Если ДатаДок = Неопределено Тогда
		ВызватьИсключение "Не заполнена дата документа.";
	КонецЕсли;
	Если Не ЗначениеЗаполнено(Данные.Покупатель.ИНН) Тогда
		ВызватьИсключение "Не заполнен ИНН покупателя.";
	КонецЕсли;

	Организация = НайтиОрганизацию(Данные.Поставщик.ИНН);
	Если Не ЗначениеЗаполнено(Организация) Тогда
		ВызватьИсключение "В базе нет организации. Заведите организацию с ИНН " + Данные.Поставщик.ИНН + ".";
	КонецЕсли;

	Контрагент = НайтиИлиСоздатьКонтрагента(Данные.Покупатель);
	ДополнитьКонтрагента(Контрагент, Данные.Покупатель);
	Договор = НайтиИлиСоздатьДоговор(Контрагент, Организация, Данные.Основание);
	Валюта = НайтиВалюту();
	ДанныеБанка = ЗначениеПоля(Данные, "Банк", Новый Структура);
	БанковскийСчет = НайтиИлиСоздатьБанковскийСчет(Организация, ДанныеБанка);
	Если Не ЗначениеЗаполнено(БанковскийСчет) Тогда
		БанковскийСчет = ОсновнойСчетОрганизации(Организация);
	КонецЕсли;
	Если Не ЗначениеЗаполнено(БанковскийСчет) Тогда
		БанковскийСчет = ПервыйБанковскийСчет(Организация);
	КонецЕсли;
	Если Не ЗначениеЗаполнено(БанковскийСчет) Тогда
		ВызватьИсключение "Реквизиты банковского счета не заполнены. В PDF нет БИК и расчетного счета, а у организации нет ни одного счета.";
	КонецЕсли;
	ДополнитьОрганизациюСчетом(Организация, БанковскийСчет);
	Ставка = СтавкаНДС(ЧислоПоля(Данные, "СтавкаНДС", -1));
	Комментарий = "Загружено из PDF расширением «Загрузка счетов и УПД». "
		+ Данные.Поставщик.Наименование + " → " + Данные.Покупатель.Наименование + ". "
		+ Данные.Основание;

	Протокол = Новый Массив;
	Протокол.Добавить("Контрагент: " + Строка(Контрагент));
	Протокол.Добавить("Банковский счет: " + Строка(БанковскийСчет));
	СчетСсылка = Документы.СчетНаОплатуПокупателю.ПустаяСсылка();

	Если СоздаватьСчет Тогда
		СуществующийСчет = НайтиСуществующий("СчетНаОплатуПокупателю", Данные.Номер, ДатаДок, Контрагент);
		Если ЗначениеЗаполнено(СуществующийСчет) Тогда
			СчетСсылка = СуществующийСчет;
			ТекстОбновления = ДополнитьСуществующийДокумент(СуществующийСчет, Данные, Организация, Контрагент, Договор, Валюта, БанковскийСчет, Ставка, Комментарий, Неопределено);
			Если ЗначениеЗаполнено(ТекстОбновления) Тогда
				Протокол.Добавить(Строка(СуществующийСчет) + ": " + ТекстОбновления);
			Иначе
				Протокол.Добавить("Счет уже есть, пустых реквизитов нет: " + Строка(СуществующийСчет));
			КонецЕсли;
		Иначе
			СчетСсылка = СоздатьСчет(Данные, ДатаДок, Организация, Контрагент, Договор, Валюта, БанковскийСчет, Ставка, Комментарий);
			Протокол.Добавить("Счет на оплату покупателю: " + Строка(СчетСсылка));
		КонецЕсли;
	КонецЕсли;

	Если СоздаватьУПД Тогда
		СуществующаяРеализация = НайтиСуществующий("РеализацияТоваровУслуг", Данные.Номер, ДатаДок, Контрагент);
		Если ЗначениеЗаполнено(СуществующаяРеализация) Тогда
			ТекстОбновления = ДополнитьСуществующийДокумент(СуществующаяРеализация, Данные, Организация, Контрагент, Договор, Валюта, БанковскийСчет, Ставка, Комментарий, СчетСсылка);
			Если ЗначениеЗаполнено(ТекстОбновления) Тогда
				Протокол.Добавить(Строка(СуществующаяРеализация) + ": " + ТекстОбновления);
			Иначе
				Протокол.Добавить("УПД уже есть, пустых реквизитов нет: " + Строка(СуществующаяРеализация));
			КонецЕсли;
			СчетФактура = НайтиСчетФактуру(СуществующаяРеализация);
			Если ЗначениеЗаполнено(СчетФактура) Тогда
				ТекстСчетаФактуры = ДополнитьСуществующийДокумент(СчетФактура, Данные, Организация, Контрагент, Договор, Валюта, БанковскийСчет, Ставка, Комментарий, СуществующаяРеализация);
				Если ЗначениеЗаполнено(ТекстСчетаФактуры) Тогда
					Протокол.Добавить(Строка(СчетФактура) + ": " + ТекстСчетаФактуры);
				КонецЕсли;
			КонецЕсли;
		Иначе
			Реализация = СоздатьРеализацию(Данные, ДатаДок, Организация, Контрагент, Договор, Валюта, БанковскийСчет, СчетСсылка, Ставка, Комментарий, Протокол);
			СчетФактура = СоздатьСчетФактуру(Данные, ДатаДок, Организация, Контрагент, Договор, Реализация, Протокол);
			Протокол.Добавить("УПД (реализация): " + Строка(Реализация));
			Протокол.Добавить("Счет-фактура выданный: " + Строка(СчетФактура));
		КонецЕсли;
	КонецЕсли;

	Возврат СтрСоединить(Протокол, Символы.ПС);

КонецФункции

Функция ЗагрузитьАрхивДиадок(ДвоичныеДанные) Экспорт

	Попытка
		Возврат ЗагрузитьАрхивДиадокВнутри(ДвоичныеДанные);
	Исключение
		Возврат "Ошибка загрузки архива:" + Символы.ПС + КраткоеПредставлениеОшибки(ИнформацияОбОшибке());
	КонецПопытки;

КонецФункции

Функция ЗагрузитьАрхивДиадокВнутри(ДвоичныеДанные)

	Если ТипЗнч(ДвоичныеДанные) <> Тип("ДвоичныеДанные") Тогда
		Возврат "Не переданы данные архива.";
	КонецЕсли;

	Ид = СтрЗаменить(Строка(Новый УникальныйИдентификатор), "-", "");
	Каталог = КаталогВременныхФайлов();
	ПутьZip = Каталог + "zs_" + Ид + ".zip";
	ПутьPS = Каталог + "zs_" + Ид + "_diadoc.ps1";
	ПутьPDF = Каталог + "zs_" + Ид + "_extract.ps1";
	ПутьJSON = Каталог + "zs_" + Ид + "_diadoc.json";
	ДвоичныеДанные.Записать(ПутьZip);

	Запись = Новый ЗаписьТекста(ПутьPS, КодировкаТекста.UTF8);
	Запись.Записать(ТекстСкриптаДиадок());
	Запись.Закрыть();
	Запись = Новый ЗаписьТекста(ПутьPDF, КодировкаТекста.UTF8);
	Запись.Записать(ТекстСкрипта());
	Запись.Закрыть();

	Команда = "powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File """
		+ ПутьPS + """ -ZipPath """ + ПутьZip + """ -OutPath """ + ПутьJSON + """ -ExtractScript """ + ПутьPDF + """";
	Попытка
		Оболочка = Новый COMОбъект("WScript.Shell");
		Оболочка.Run(Команда, 0, Истина);
	Исключение
		УдалитьВременные(ПутьZip, ПутьPS, ПутьJSON);
		УдалитьВременные(ПутьPDF, "", "");
		Возврат "Не удалось запустить PowerShell. Снимите безопасный режим расширения. "
			+ КраткоеПредставлениеОшибки(ИнформацияОбОшибке());
	КонецПопытки;

	Файл = Новый Файл(ПутьJSON);
	Если Не Файл.Существует() Тогда
		УдалитьВременные(ПутьZip, ПутьPS, ПутьJSON);
		УдалитьВременные(ПутьPDF, "", "");
		Возврат "PowerShell не вернул разбор архива Диадока.";
	КонецЕсли;
	ЧтениеТекста = Новый ЧтениеТекста(ПутьJSON, КодировкаТекста.UTF8);
	ТекстJSON = ЧтениеТекста.Прочитать();
	ЧтениеТекста.Закрыть();
	УдалитьВременные(ПутьZip, ПутьPS, ПутьJSON);
	УдалитьВременные(ПутьPDF, "", "");

	Чтение = Новый ЧтениеJSON;
	Чтение.УстановитьСтроку(ТекстJSON);
	Корень = ПрочитатьJSON(Чтение);
	ОшибкаАрхива = ЗначениеПоля(Корень, "Ошибка", "");
	Если ЗначениеЗаполнено(ОшибкаАрхива) Тогда
		Возврат Строка(ОшибкаАрхива);
	КонецЕсли;

	СписокДокументов = ЗначениеПоля(Корень, "Документы", Новый Массив);
	Если ТипЗнч(СписокДокументов) <> Тип("Массив") Тогда
		Список = Новый Массив;
		Список.Добавить(СписокДокументов);
		СписокДокументов = Список;
	КонецЕсли;

	Протокол = Новый Массив;
	Связи = Новый Массив;
	Создано = 0;
	Пропущено = 0;
	Для Каждого Документ Из СписокДокументов Цикл
		Вид = Строка(ЗначениеПоля(Документ, "Вид", ""));
		ИмяФайла = Строка(ЗначениеПоля(Документ, "ИмяФайла", ""));
		Если Вид = "Договор" Тогда
			Протокол.Добавить(УчестьДоговорАрхива(Документ));
			Продолжить;
		КонецЕсли;
		Если Вид = "Прочее" Или Вид = "АктСверки" Или Вид = "Доверенность" Или Вид = "Заявка" Или Вид = "Письмо" Тогда
			Причина = Строка(ЗначениеПоля(Документ, "Причина", "В учет не проводится."));
			Протокол.Добавить(ИмяФайла + ": пропущен. " + Причина);
			Пропущено = Пропущено + 1;
			Продолжить;
		КонецЕсли;
		Если Вид <> "Счет" И Вид <> "УПД" Тогда
			Протокол.Добавить(ИмяФайла + ": пропущен, неизвестный вид " + Вид);
			Пропущено = Пропущено + 1;
			Продолжить;
		КонецЕсли;

		СсылкаПоИд = НайтиПоИдентификатору(Строка(ЗначениеПоля(Документ, "Ид", "")));
		Если ЗначениеЗаполнено(СсылкаПоИд) Тогда
			Протокол.Добавить(ИмяФайла + ": уже есть в базе, дубль не создан (" + Строка(СсылкаПоИд) + ").");
			Пропущено = Пропущено + 1;
			Связи.Добавить(ОписаниеСвязи(Документ, СсылкаПоИд));
			Продолжить;
		КонецЕсли;

		Если Вид = "Счет" Тогда
			Документ.Вставить("СоздатьСчет", Истина);
			Документ.Вставить("СоздатьУПД", Ложь);
		Иначе
			Документ.Вставить("СоздатьСчет", Ложь);
			Документ.Вставить("СоздатьУПД", Истина);
		КонецЕсли;

		ЗаписьJSON = Новый ЗаписьJSON;
		ЗаписьJSON.УстановитьСтроку();
		ЗаписатьJSON(ЗаписьJSON, Документ);
		Попытка
			ТекстСоздания = СоздатьДокументы(ЗаписьJSON.Закрыть());
			Протокол.Добавить(ИмяФайла + ": " + ТекстСоздания);
			Если СтрНайти(ТекстСоздания, "уже есть") > 0 Или СтрНайти(ТекстСоздания, "дополнено") > 0 Тогда
				Пропущено = Пропущено + 1;
			Иначе
				Создано = Создано + 1;
			КонецЕсли;
		Исключение
			Протокол.Добавить(ИмяФайла + ": " + КраткоеПредставлениеОшибки(ИнформацияОбОшибке()));
			Продолжить;
		КонецПопытки;
		Связи.Добавить(ОписаниеСвязи(Документ, Неопределено));
	КонецЦикла;

	Протокол.Добавить(СвязатьДокументыАрхива(Связи));
	Протокол.Вставить(0, "Архив Диадок. Создано пакетов: " + Формат(Создано, "ЧГ=0")
		+ ", уже было или не проводится: " + Формат(Пропущено, "ЧГ=0") + ".");
	Возврат СтрСоединить(Протокол, Символы.ПС);

КонецФункции

Функция ОписаниеСвязи(Документ, СсылкаПоИд)

	Покупатель = ЗначениеПоля(Документ, "Покупатель", Новый Структура);
	Вид = Строка(ЗначениеПоля(Документ, "Вид", ""));
	Счет = Документы.СчетНаОплатуПокупателю.ПустаяСсылка();
	Реализация = Документы.РеализацияТоваровУслуг.ПустаяСсылка();
	Если ТипЗнч(СсылкаПоИд) = Тип("ДокументСсылка.СчетНаОплатуПокупателю") Тогда
		Счет = СсылкаПоИд;
	ИначеЕсли ТипЗнч(СсылкаПоИд) = Тип("ДокументСсылка.РеализацияТоваровУслуг") Тогда
		Реализация = СсылкаПоИд;
	ИначеЕсли ТипЗнч(СсылкаПоИд) = Тип("ДокументСсылка.СчетФактураВыданный") Тогда
		Реализация = РеализацияСчетаФактуры(СсылкаПоИд);
	КонецЕсли;
	Возврат Новый Структура("Вид,ИНН,Пакет,Договор,ПлатежкаНомер,ПлатежкаДата,Счет,Реализация,Номер,Дата",
		Вид,
		Строка(ЗначениеПоля(Покупатель, "ИНН", ЗначениеПоля(Документ, "ИННПапки", ""))),
		Строка(ЗначениеПоля(Документ, "Пакет", "")),
		КлючДоговора(Строка(ЗначениеПоля(Документ, "Основание", ""))),
		Строка(ЗначениеПоля(Документ, "ПлатежкаНомер", "")),
		Строка(ЗначениеПоля(Документ, "ПлатежкаДата", "")),
		Счет,
		Реализация,
		Строка(ЗначениеПоля(Документ, "Номер", "")),
		ЗначениеПоля(Документ, "Дата", ""));

КонецФункции

Функция СвязатьДокументыАрхива(Связи)

	Строки = Новый Массив;
	Для Каждого Связь Из Связи Цикл
		Если Связь.Вид = "Счет" И Не ЗначениеЗаполнено(Связь.Счет) Тогда
			Связь.Счет = НайтиСсылкуЗагрузки("СчетНаОплатуПокупателю", Связь);
		ИначеЕсли Связь.Вид = "УПД" И Не ЗначениеЗаполнено(Связь.Реализация) Тогда
			Связь.Реализация = НайтиСсылкуЗагрузки("РеализацияТоваровУслуг", Связь);
		КонецЕсли;
	КонецЦикла;

	Для Каждого УПД Из Связи Цикл
		Если УПД.Вид <> "УПД" Или Не ЗначениеЗаполнено(УПД.Реализация) Тогда
			Продолжить;
		КонецЕсли;
		Счет = НайтиСчетДляУПД(Связи, УПД);
		Если ЗначениеЗаполнено(Счет) И ПривязатьСчетКРеализации(УПД.Реализация, Счет) Тогда
			Строки.Добавить("Связь: " + Строка(УПД.Реализация) + " <- " + Строка(Счет));
		КонецЕсли;
		Если ЗначениеЗаполнено(УПД.ПлатежкаНомер) Тогда
			Поступление = НайтиПоступлениеОплаты(УПД.ПлатежкаНомер, УПД.ПлатежкаДата);
			Если ЗначениеЗаполнено(Поступление) Тогда
				ДописатьОплатуВКомментарий(УПД.Реализация, УПД.ПлатежкаНомер, Поступление);
				Строки.Добавить("Оплата УПД " + Строка(УПД.Реализация) + ": " + Строка(Поступление));
			КонецЕсли;
		КонецЕсли;
	КонецЦикла;
	Если Строки.Количество() = 0 Тогда
		Возврат "Новых связей между документами не добавлено.";
	КонецЕсли;
	Возврат СтрСоединить(Строки, Символы.ПС);

КонецФункции

Функция НайтиСчетДляУПД(Связи, УПД)

	ПоПакету = Новый Массив;
	ПоДоговору = Новый Массив;
	Для Каждого Связь Из Связи Цикл
		Если Связь.Вид <> "Счет" Или Не ЗначениеЗаполнено(Связь.Счет) Тогда
			Продолжить;
		КонецЕсли;
		Если ЗначениеЗаполнено(УПД.Пакет) И Связь.Пакет = УПД.Пакет Тогда
			ПоПакету.Добавить(Связь.Счет);
		КонецЕсли;
		Если ЗначениеЗаполнено(УПД.Договор) И Связь.ИНН = УПД.ИНН И Связь.Договор = УПД.Договор Тогда
			ПоДоговору.Добавить(Связь.Счет);
		КонецЕсли;
	КонецЦикла;
	Если ПоПакету.Количество() = 1 Тогда
		Возврат ПоПакету[0];
	КонецЕсли;
	Если ПоДоговору.Количество() = 1 Тогда
		Возврат ПоДоговору[0];
	КонецЕсли;
	Возврат Документы.СчетНаОплатуПокупателю.ПустаяСсылка();

КонецФункции

Функция НайтиСсылкуЗагрузки(ИмяДокумента, Связь)

	ДатаДок = ДатаИзСтроки(Связь.Дата);
	Если ДатаДок = Неопределено Или Не ЗначениеЗаполнено(Связь.Номер) Или Не ЗначениеЗаполнено(Связь.ИНН) Тогда
		Возврат Неопределено;
	КонецЕсли;
	Контрагент = НайтиКонтрагентаПоИНН(Связь.ИНН);
	Если Не ЗначениеЗаполнено(Контрагент) Тогда
		Возврат Неопределено;
	КонецЕсли;
	Возврат НайтиСуществующий(ИмяДокумента, Связь.Номер, ДатаДок, Контрагент);

КонецФункции

Функция ПривязатьСчетКРеализации(Реализация, Счет)

	Объект = Реализация.ПолучитьОбъект();
	Если Объект.Метаданные().Реквизиты.Найти("СчетНаОплатуПокупателю") = Неопределено Тогда
		Возврат Ложь;
	КонецЕсли;
	Если ЗначениеЗаполнено(Объект.СчетНаОплатуПокупателю) Тогда
		Возврат Ложь;
	КонецЕсли;
	Объект.СчетНаОплатуПокупателю = Счет;
	Попытка
		Если Объект.Проведен Тогда
			Объект.Записать(РежимЗаписиДокумента.Проведение);
		Иначе
			Объект.Записать(РежимЗаписиДокумента.Запись);
		КонецЕсли;
	Исключение
		Попытка
			Объект.Записать(РежимЗаписиДокумента.Запись);
		Исключение
			Возврат Ложь;
		КонецПопытки;
	КонецПопытки;
	Возврат Истина;

КонецФункции

Процедура ДописатьОплатуВКомментарий(Реализация, НомерПлатежки, Поступление)

	Объект = Реализация.ПолучитьОбъект();
	Если Объект.Метаданные().Реквизиты.Найти("Комментарий") = Неопределено Тогда
		Возврат;
	КонецЕсли;
	Если СтрНайти(Строка(Объект.Комментарий), НомерПлатежки) > 0 Тогда
		Возврат;
	КонецЕсли;
	Объект.Комментарий = СокрЛП(Строка(Объект.Комментарий) + " Оплата ПП " + НомерПлатежки + ": " + Строка(Поступление));
	Попытка
		Объект.Записать(РежимЗаписиДокумента.Запись);
	Исключение
		Возврат;
	КонецПопытки;

КонецПроцедуры

Функция НайтиПоступлениеОплаты(Номер, ДатаТекст)

	ДатаДок = ДатаИзСтроки(ДатаТекст);
	Если Не ЗначениеЗаполнено(Номер) Или ДатаДок = Неопределено Тогда
		Возврат Неопределено;
	КонецЕсли;
	Если Метаданные.Документы.Найти("ПоступлениеНаРасчетныйСчет") = Неопределено Тогда
		Возврат Неопределено;
	КонецЕсли;
	Запрос = Новый Запрос;
	Запрос.Текст =
	"ВЫБРАТЬ ПЕРВЫЕ 1
	|	Оплата.Ссылка КАК Ссылка
	|ИЗ
	|	Документ.ПоступлениеНаРасчетныйСчет КАК Оплата
	|ГДЕ
	|	НЕ Оплата.ПометкаУдаления
	|	И Оплата.НомерВходящегоДокумента = &Номер
	|	И Оплата.ДатаВходящегоДокумента = &Дата";
	Запрос.УстановитьПараметр("Номер", Номер);
	Запрос.УстановитьПараметр("Дата", ДатаДок);
	Попытка
		Выборка = Запрос.Выполнить().Выбрать();
	Исключение
		Возврат Неопределено;
	КонецПопытки;
	Если Выборка.Следующий() Тогда
		Возврат Выборка.Ссылка;
	КонецЕсли;
	Возврат Неопределено;

КонецФункции

Функция УчестьДоговорАрхива(Документ)

	ИНН = Строка(ЗначениеПоля(Документ, "ИННПапки", ""));
	Наименование = Строка(ЗначениеПоля(Документ, "Наименование", ЗначениеПоля(Документ, "Основание", "")));
	Если Не ЗначениеЗаполнено(ИНН) Или Не ЗначениеЗаполнено(Наименование) Тогда
		Возврат Строка(ЗначениеПоля(Документ, "ИмяФайла", "Договор")) + ": пропущен, нет ИНН или названия.";
	КонецЕсли;
	Контрагент = НайтиКонтрагентаПоИНН(ИНН);
	Если Не ЗначениеЗаполнено(Контрагент) Тогда
		Возврат Наименование + ": договор не создан, контрагент с ИНН " + ИНН + " не найден. Дубль не создается.";
	КонецЕсли;
	Организация = НайтиОрганизацию("7717552784");
	Договор = НайтиИлиСоздатьДоговор(Контрагент, Организация, Наименование);
	Возврат "Договор учтен без дубля: " + Строка(Договор);

КонецФункции

Функция НайтиКонтрагентаПоИНН(ИНН)

	Запрос = Новый Запрос;
	Запрос.Текст =
	"ВЫБРАТЬ ПЕРВЫЕ 1
	|	Контрагенты.Ссылка КАК Ссылка
	|ИЗ
	|	Справочник.Контрагенты КАК Контрагенты
	|ГДЕ
	|	Контрагенты.ИНН = &ИНН
	|	И НЕ Контрагенты.ПометкаУдаления";
	Запрос.УстановитьПараметр("ИНН", ИНН);
	Выборка = Запрос.Выполнить().Выбрать();
	Если Выборка.Следующий() Тогда
		Возврат Выборка.Ссылка;
	КонецЕсли;
	Возврат Справочники.Контрагенты.ПустаяСсылка();

КонецФункции

Функция НайтиПоИдентификатору(Ид)

	Ид = СокрЛП(Ид);
	Если СтрДлина(Ид) <> 36 Тогда
		Возврат Неопределено;
	КонецЕсли;
	Попытка
		УИД = Новый УникальныйИдентификатор(Ид);
	Исключение
		Возврат Неопределено;
	КонецПопытки;
	Имена = СтрРазделить("РеализацияТоваровУслуг,СчетФактураВыданный,СчетНаОплатуПокупателю", ",");
	Для Каждого Имя Из Имена Цикл
		Ссылка = Документы[Имя].ПолучитьСсылку(УИД);
		Запрос = Новый Запрос;
		Запрос.Текст = "ВЫБРАТЬ ПЕРВЫЕ 1 Док.Ссылка КАК Ссылка ИЗ Документ." + Имя + " КАК Док ГДЕ Док.Ссылка = &Ссылка";
		Запрос.УстановитьПараметр("Ссылка", Ссылка);
		Попытка
			Выборка = Запрос.Выполнить().Выбрать();
		Исключение
			Продолжить;
		КонецПопытки;
		Если Выборка.Следующий() Тогда
			Возврат Выборка.Ссылка;
		КонецЕсли;
	КонецЦикла;
	Возврат Неопределено;

КонецФункции

Функция РеализацияСчетаФактуры(СчетФактура)

	Попытка
		Основание = СчетФактура.ДокументОснование;
		Если ТипЗнч(Основание) = Тип("ДокументСсылка.РеализацияТоваровУслуг") Тогда
			Возврат Основание;
		КонецЕсли;
	Исключение
		Возврат Документы.РеализацияТоваровУслуг.ПустаяСсылка();
	КонецПопытки;
	Возврат Документы.РеализацияТоваровУслуг.ПустаяСсылка();

КонецФункции

Функция КлючДоговора(Основание)

	Текст = НРег(СокрЛП(Основание));
	Текст = СтрЗаменить(Текст, "№№", "№");
	Текст = СтрЗаменить(Текст, "  ", " ");
	Возврат Текст;

КонецФункции

#КонецОбласти

#Область СлужебныеПроцедурыИФункции

Функция ИзвлечьJSON(ДвоичныеДанные)

	Ид = СтрЗаменить(Строка(Новый УникальныйИдентификатор), "-", "");
	ПутьPDF = КаталогВременныхФайлов() + "zs_" + Ид + ".pdf";
	ПутьPS = КаталогВременныхФайлов() + "zs_" + Ид + ".ps1";
	ПутьJSON = КаталогВременныхФайлов() + "zs_" + Ид + ".json";

	ДвоичныеДанные.Записать(ПутьPDF);
	Запись = Новый ЗаписьТекста(ПутьPS, КодировкаТекста.UTF8);
	Запись.Записать(ТекстСкрипта());
	Запись.Закрыть();

	Команда = "powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File """
		+ ПутьPS + """ -PdfPath """ + ПутьPDF + """ -OutPath """ + ПутьJSON + """";

	Попытка
		Оболочка = Новый COMОбъект("WScript.Shell");
		Оболочка.Run(Команда, 0, Истина);
	Исключение
		УдалитьВременные(ПутьPDF, ПутьPS, ПутьJSON);
		Возврат "{""Ошибка"":""Не удалось запустить PowerShell. Снимите безопасный режим расширения и флажок защиты от опасных действий. "
			+ Экранировать(КраткоеПредставлениеОшибки(ИнформацияОбОшибке())) + """}";
	КонецПопытки;

	Файл = Новый Файл(ПутьJSON);
	Если Не Файл.Существует() Тогда
		УдалитьВременные(ПутьPDF, ПутьPS, ПутьJSON);
		Возврат "{""Ошибка"":""PowerShell не вернул результат разбора PDF.""}";
	КонецЕсли;

	Чтение = Новый ЧтениеТекста(ПутьJSON, КодировкаТекста.UTF8);
	Текст = Чтение.Прочитать();
	Чтение.Закрыть();
	УдалитьВременные(ПутьPDF, ПутьPS, ПутьJSON);

	Если Не ЗначениеЗаполнено(Текст) Тогда
		Возврат "{""Ошибка"":""Пустой ответ разбора PDF.""}";
	КонецЕсли;

	Возврат Текст;

КонецФункции

Функция ТекстСкрипта()

	Б64 = "cGFyYW0oCiAgICBbUGFyYW1ldGVyKE1hbmRhdG9yeSA9ICR0cnVlKV1bc3RyaW5nXSRQZGZQYXRoLAogICAgW1BhcmFtZXRlcihNYW5kYXRvcnkgPSAkdHJ1ZSldW3N0cmluZ10kT3V0UGF0aAopCgokRXJyb3JBY3Rpb25QcmVmZXJlbmNl"
	+ "ID0gIlN0b3AiCkFkZC1UeXBlIC1Bc3NlbWJseU5hbWUgU3lzdGVtLklPLkNvbXByZXNzaW9uCgpmdW5jdGlvbiBXcml0ZS1FcnJvckpzb24oW3N0cmluZ10kTWVzc2FnZSkgewogICAgJHBheWxvYWQgPSBAeyDQntGI0LjQsdC60LAgPSAk"
	+ "TWVzc2FnZSB9IHwgQ29udmVydFRvLUpzb24gLUNvbXByZXNzCiAgICBbU3lzdGVtLklPLkZpbGVdOjpXcml0ZUFsbFRleHQoJE91dFBhdGgsICRwYXlsb2FkLCBbU3lzdGVtLlRleHQuVVRGOEVuY29kaW5nXTo6bmV3KCRmYWxzZSkpCn0K"
	+ "CmZ1bmN0aW9uIEluZmxhdGUtWmxpYihbYnl0ZVtdXSRSYXcpIHsKICAgIGlmICgkbnVsbCAtZXEgJFJhdyAtb3IgJFJhdy5MZW5ndGggLWx0IDMpIHsgcmV0dXJuICRudWxsIH0KICAgICRza2lwID0gMgogICAgaWYgKCRSYXdbMF0gLWVx"
	+ "IDEyMCAtYW5kICgoJFJhd1sxXSAtYmFuZCAzMikgLW5lIDApKSB7ICRza2lwID0gNiB9CiAgICBpZiAoJFJhdy5MZW5ndGggLWxlICRza2lwKSB7IHJldHVybiAkbnVsbCB9CiAgICAkbGVuID0gJFJhdy5MZW5ndGggLSAkc2tpcAogICAg"
	+ "JHBheWxvYWQgPSBOZXctT2JqZWN0IGJ5dGVbXSAkbGVuCiAgICBbU3lzdGVtLkFycmF5XTo6Q29weSgkUmF3LCAkc2tpcCwgJHBheWxvYWQsIDAsICRsZW4pCiAgICAkaW5wdXQgPSBOZXctT2JqZWN0IFN5c3RlbS5JTy5NZW1vcnlTdHJl"
	+ "YW0oLCRwYXlsb2FkKQogICAgJGRlZmxhdGUgPSBOZXctT2JqZWN0IFN5c3RlbS5JTy5Db21wcmVzc2lvbi5EZWZsYXRlU3RyZWFtKCRpbnB1dCwgW1N5c3RlbS5JTy5Db21wcmVzc2lvbi5Db21wcmVzc2lvbk1vZGVdOjpEZWNvbXByZXNz"
	+ "KQogICAgJG91dHB1dCA9IE5ldy1PYmplY3QgU3lzdGVtLklPLk1lbW9yeVN0cmVhbQogICAgdHJ5IHsKICAgICAgICAkZGVmbGF0ZS5Db3B5VG8oJG91dHB1dCkKICAgIH0gY2F0Y2ggewogICAgICAgIHJldHVybiAkbnVsbAogICAgfSBm"
	+ "aW5hbGx5IHsKICAgICAgICAkZGVmbGF0ZS5EaXNwb3NlKCkKICAgICAgICAkaW5wdXQuRGlzcG9zZSgpCiAgICB9CiAgICByZXR1cm4gJG91dHB1dC5Ub0FycmF5KCkKfQoKZnVuY3Rpb24gR2V0LVN0cmVhbUJ5dGVzKFtzdHJpbmddJEJv"
	+ "ZHkpIHsKICAgICRtYXRjaCA9IFtyZWdleF06Ok1hdGNoKCRCb2R5LCAic3RyZWFtXHI/XG4oW1xzXFNdKj8pXHI/XG5lbmRzdHJlYW0iKQogICAgaWYgKC1ub3QgJG1hdGNoLlN1Y2Nlc3MpIHsgcmV0dXJuICRudWxsIH0KICAgICRsYXRp"
	+ "biA9IFtTeXN0ZW0uVGV4dC5FbmNvZGluZ106OkdldEVuY29kaW5nKDI4NTkxKQogICAgJHJhdyA9ICRsYXRpbi5HZXRCeXRlcygkbWF0Y2guR3JvdXBzWzFdLlZhbHVlKQogICAgJGhlYWQgPSAkQm9keS5TdWJzdHJpbmcoMCwgW01hdGhd"
	+ "OjpNaW4oJG1hdGNoLkluZGV4LCAkQm9keS5MZW5ndGgpKQogICAgaWYgKCRoZWFkIC1tYXRjaCAiRmxhdGVEZWNvZGUiKSB7CiAgICAgICAgJGluZmxhdGVkID0gSW5mbGF0ZS1abGliICRyYXcKICAgICAgICBpZiAoJG51bGwgLW5lICRp"
	+ "bmZsYXRlZCkgeyByZXR1cm4gJGluZmxhdGVkIH0KICAgIH0KICAgIHJldHVybiAkcmF3Cn0KCmZ1bmN0aW9uIFBhcnNlLUNNYXAoW3N0cmluZ10kQ01hcFRleHQpIHsKICAgICRtYXAgPSBAe30KICAgICRibG9ja3MgPSAkQ01hcFRleHQg"
	+ "LXNwbGl0ICJiZWdpbmJmY2hhciIKICAgIGZvciAoJGkgPSAxOyAkaSAtbHQgJGJsb2Nrcy5Db3VudDsgJGkrKykgewogICAgICAgICRwYXJ0ID0gKCRibG9ja3NbJGldIC1zcGxpdCAiZW5kYmZjaGFyIilbMF0KICAgICAgICBmb3JlYWNo"
	+ "ICgkcGFpciBpbiBbcmVnZXhdOjpNYXRjaGVzKCRwYXJ0LCAiPChbMC05QS1GYS1mXSspPlxzKjwoWzAtOUEtRmEtZl0rKT4iKSkgewogICAgICAgICAgICAkc3JjID0gW0NvbnZlcnRdOjpUb0ludDMyKCRwYWlyLkdyb3Vwc1sxXS5WYWx1"
	+ "ZSwgMTYpCiAgICAgICAgICAgICRkc3QgPSAkcGFpci5Hcm91cHNbMl0uVmFsdWUKICAgICAgICAgICAgJGNoYXJzID0gIiIKICAgICAgICAgICAgZm9yICgkayA9IDA7ICRrICsgNCAtbGUgJGRzdC5MZW5ndGg7ICRrICs9IDQpIHsKICAg"
	+ "ICAgICAgICAgICAgICRjaGFycyArPSBbY2hhcl1bQ29udmVydF06OlRvSW50MzIoJGRzdC5TdWJzdHJpbmcoJGssIDQpLCAxNikKICAgICAgICAgICAgfQogICAgICAgICAgICAkbWFwWyRzcmNdID0gJGNoYXJzCiAgICAgICAgfQogICAg"
	+ "fQogICAgcmV0dXJuICRtYXAKfQoKZnVuY3Rpb24gRGVjb2RlLVBkZlN0cmluZyhbc3RyaW5nXSRWYWx1ZSwgJE1hcCkgewogICAgJGJ5dGVzID0gTmV3LU9iamVjdCBTeXN0ZW0uQ29sbGVjdGlvbnMuR2VuZXJpYy5MaXN0W2ludF0KICAg"
	+ "IGZvciAoJGkgPSAwOyAkaSAtbHQgJFZhbHVlLkxlbmd0aDsgJGkrKykgewogICAgICAgICRjaCA9ICRWYWx1ZVskaV0KICAgICAgICBpZiAoJGNoIC1lcSAiXCIpIHsKICAgICAgICAgICAgJG5leHQgPSBpZiAoJGkgKyAxIC1sdCAkVmFs"
	+ "dWUuTGVuZ3RoKSB7ICRWYWx1ZVskaSArIDFdIH0gZWxzZSB7ICIiIH0KICAgICAgICAgICAgaWYgKCRuZXh0IC1tYXRjaCAiWzAtN10iKSB7CiAgICAgICAgICAgICAgICAkb2N0ID0gIiIKICAgICAgICAgICAgICAgICRqID0gMQogICAg"
	+ "ICAgICAgICAgICAgd2hpbGUgKCRqIC1sZSAzIC1hbmQgKCRpICsgJGopIC1sdCAkVmFsdWUuTGVuZ3RoIC1hbmQgJFZhbHVlWyRpICsgJGpdIC1tYXRjaCAiWzAtN10iKSB7CiAgICAgICAgICAgICAgICAgICAgJG9jdCArPSAkVmFsdWVb"
	+ "JGkgKyAkal0KICAgICAgICAgICAgICAgICAgICAkaisrCiAgICAgICAgICAgICAgICB9CiAgICAgICAgICAgICAgICAkYnl0ZXMuQWRkKFtDb252ZXJ0XTo6VG9JbnQzMigkb2N0LCA4KSkKICAgICAgICAgICAgICAgICRpICs9ICRqIC0g"
	+ "MQogICAgICAgICAgICB9IGVsc2UgewogICAgICAgICAgICAgICAgJGJ5dGVzLkFkZChbaW50XVtjaGFyXSRuZXh0KQogICAgICAgICAgICAgICAgJGkrKwogICAgICAgICAgICB9CiAgICAgICAgfSBlbHNlIHsKICAgICAgICAgICAgJGJ5"
	+ "dGVzLkFkZCgoW2ludF1bY2hhcl0kY2gpIC1iYW5kIDI1NSkKICAgICAgICB9CiAgICB9CiAgICAkdHdvID0gJGZhbHNlCiAgICBmb3JlYWNoICgka2V5IGluICRNYXAuS2V5cykgeyBpZiAoW2ludF0ka2V5IC1ndCAyNTUpIHsgJHR3byA9"
	+ "ICR0cnVlOyBicmVhayB9IH0KICAgICR0ZXh0ID0gIiIKICAgIGlmICgkdHdvKSB7CiAgICAgICAgZm9yICgkaSA9IDA7ICRpICsgMSAtbHQgJGJ5dGVzLkNvdW50OyAkaSArPSAyKSB7CiAgICAgICAgICAgICRjb2RlID0gKCRieXRlc1sk"
	+ "aV0gLXNobCA4KSAtYm9yICRieXRlc1skaSArIDFdCiAgICAgICAgICAgIGlmICgkTWFwLkNvbnRhaW5zS2V5KCRjb2RlKSkgeyAkdGV4dCArPSAkTWFwWyRjb2RlXSB9CiAgICAgICAgfQogICAgfSBlbHNlIHsKICAgICAgICBmb3JlYWNo"
	+ "ICgkYiBpbiAkYnl0ZXMpIHsKICAgICAgICAgICAgaWYgKCRNYXAuQ29udGFpbnNLZXkoJGIpKSB7ICR0ZXh0ICs9ICRNYXBbJGJdIH0KICAgICAgICB9CiAgICB9CiAgICByZXR1cm4gJHRleHQKfQoKZnVuY3Rpb24gSW52b2tlLUV4dHJh"
	+ "Y3Qgewp0cnkgewogICAgJGZpbGVCeXRlcyA9IFtTeXN0ZW0uSU8uRmlsZV06OlJlYWRBbGxCeXRlcygkUGRmUGF0aCkKICAgICRsYXRpbiA9IFtTeXN0ZW0uVGV4dC5FbmNvZGluZ106OkdldEVuY29kaW5nKDI4NTkxKQogICAgJHNvdXJj"
	+ "ZSA9ICRsYXRpbi5HZXRTdHJpbmcoJGZpbGVCeXRlcykKICAgICRvYmplY3RzID0gQHt9CiAgICBmb3JlYWNoICgkb2JqIGluIFtyZWdleF06Ok1hdGNoZXMoJHNvdXJjZSwgIihcZCspXHMrMFxzK29iaihbXHNcU10qPyllbmRvYmoiKSkg"
	+ "ewogICAgICAgICRvYmplY3RzW1tpbnRdJG9iai5Hcm91cHNbMV0uVmFsdWVdID0gJG9iai5Hcm91cHNbMl0uVmFsdWUKICAgIH0KCiAgICAkZm9udE1hcHMgPSBAe30KICAgIGZvcmVhY2ggKCRpZCBpbiBAKCRvYmplY3RzLktleXMpKSB7"
	+ "CiAgICAgICAgJGJvZHkgPSAkb2JqZWN0c1skaWRdCiAgICAgICAgJHRvID0gW3JlZ2V4XTo6TWF0Y2goJGJvZHksICIvVG9Vbmljb2RlXHMrKFxkKylccyswXHMrUiIpCiAgICAgICAgaWYgKC1ub3QgJHRvLlN1Y2Nlc3MpIHsgY29udGlu"
	+ "dWUgfQogICAgICAgICR0YXJnZXRJZCA9IFtpbnRdJHRvLkdyb3Vwc1sxXS5WYWx1ZQogICAgICAgIGlmICgtbm90ICRvYmplY3RzLkNvbnRhaW5zS2V5KCR0YXJnZXRJZCkpIHsgY29udGludWUgfQogICAgICAgICRzdHJlYW0gPSBHZXQt"
	+ "U3RyZWFtQnl0ZXMgJG9iamVjdHNbJHRhcmdldElkXQogICAgICAgIGlmICgkbnVsbCAtZXEgJHN0cmVhbSkgeyBjb250aW51ZSB9CiAgICAgICAgJGZvbnRNYXBzWyRpZF0gPSBQYXJzZS1DTWFwICgkbGF0aW4uR2V0U3RyaW5nKCRzdHJl"
	+ "YW0pKQogICAgfQoKICAgICRwYWdlcyA9IE5ldy1PYmplY3QgU3lzdGVtLkNvbGxlY3Rpb25zLkdlbmVyaWMuTGlzdFtzdHJpbmddCiAgICBmb3JlYWNoICgkaWQgaW4gQCgkb2JqZWN0cy5LZXlzKSkgewogICAgICAgICRib2R5ID0gJG9i"
	+ "amVjdHNbJGlkXQogICAgICAgIGlmICgkYm9keSAtbm90bWF0Y2ggIi9Db250ZW50cyIgLW9yICRib2R5IC1ub3RtYXRjaCAiL0ZvbnQiKSB7IGNvbnRpbnVlIH0KICAgICAgICAkZm9udEJsb2NrID0gW3JlZ2V4XTo6TWF0Y2goJGJvZHks"
	+ "ICIvRm9udFxzKjw8KFtcc1xTXSo/KT4+IikKICAgICAgICBpZiAoLW5vdCAkZm9udEJsb2NrLlN1Y2Nlc3MpIHsgY29udGludWUgfQogICAgICAgICRmb250cyA9IEB7fQogICAgICAgIGZvcmVhY2ggKCRmb250IGluIFtyZWdleF06Ok1h"
	+ "dGNoZXMoJGZvbnRCbG9jay5Hcm91cHNbMV0uVmFsdWUsICIvKEZcZCspXHMrKFxkKylccyswXHMrUiIpKSB7CiAgICAgICAgICAgICRmb250c1skZm9udC5Hcm91cHNbMV0uVmFsdWVdID0gW2ludF0kZm9udC5Hcm91cHNbMl0uVmFsdWUK"
	+ "ICAgICAgICB9CiAgICAgICAgJGNvbnRlbnRzID0gW3JlZ2V4XTo6TWF0Y2goJGJvZHksICIvQ29udGVudHNccysoXGQrKVxzKzBccytSIikKICAgICAgICBpZiAoLW5vdCAkY29udGVudHMuU3VjY2VzcykgeyBjb250aW51ZSB9CiAgICAg"
	+ "ICAgJGNvbnRlbnRJZCA9IFtpbnRdJGNvbnRlbnRzLkdyb3Vwc1sxXS5WYWx1ZQogICAgICAgIGlmICgtbm90ICRvYmplY3RzLkNvbnRhaW5zS2V5KCRjb250ZW50SWQpKSB7IGNvbnRpbnVlIH0KICAgICAgICAkc3RyZWFtID0gR2V0LVN0"
	+ "cmVhbUJ5dGVzICRvYmplY3RzWyRjb250ZW50SWRdCiAgICAgICAgaWYgKCRudWxsIC1lcSAkc3RyZWFtKSB7IGNvbnRpbnVlIH0KICAgICAgICAkd29yayA9ICRsYXRpbi5HZXRTdHJpbmcoJHN0cmVhbSkKICAgICAgICAkdG9rZW4gPSBb"
	+ "cmVnZXhdIi8oRlxkKylccytbMC05Ll0rXHMrVGZ8KC0/XGQrXC5cZCt8LT9cZCspXHMrKC0/XGQrXC5cZCt8LT9cZCspXHMrVGR8XFsoKD86XFxbXHNcU118W15cXVxcXSkqKVxdXHMqVEp8XGJCVFxiIgogICAgICAgICR4ID0gMC4wCiAg"
	+ "ICAgICAgJHkgPSAwLjAKICAgICAgICAkZm9udE5hbWUgPSAkbnVsbAogICAgICAgICRpdGVtcyA9IEAoKQogICAgICAgIGZvcmVhY2ggKCR0b2sgaW4gW3JlZ2V4XTo6TWF0Y2hlcygkd29yaywgJHRva2VuKSkgewogICAgICAgICAgICAk"
	+ "cGllY2UgPSAkdG9rLlZhbHVlCiAgICAgICAgICAgIGlmICgkcGllY2UgLWVxICJCVCIpIHsgJHggPSAwOyAkeSA9IDA7IGNvbnRpbnVlIH0KICAgICAgICAgICAgaWYgKCR0b2suR3JvdXBzWzFdLlN1Y2Nlc3MpIHsgJGZvbnROYW1lID0g"
	+ "JHRvay5Hcm91cHNbMV0uVmFsdWU7IGNvbnRpbnVlIH0KICAgICAgICAgICAgaWYgKCRwaWVjZSAtbWF0Y2ggIlRkJCIpIHsKICAgICAgICAgICAgICAgICR4ICs9IFtkb3VibGVdJHRvay5Hcm91cHNbMl0uVmFsdWUKICAgICAgICAgICAg"
	+ "ICAgICR5ICs9IFtkb3VibGVdJHRvay5Hcm91cHNbM10uVmFsdWUKICAgICAgICAgICAgICAgIGNvbnRpbnVlCiAgICAgICAgICAgIH0KICAgICAgICAgICAgaWYgKC1ub3QgJHRvay5Hcm91cHNbNF0uU3VjY2VzcyAtb3IgLW5vdCAkZm9u"
	+ "dE5hbWUpIHsgY29udGludWUgfQogICAgICAgICAgICBpZiAoLW5vdCAkZm9udHMuQ29udGFpbnNLZXkoJGZvbnROYW1lKSkgeyBjb250aW51ZSB9CiAgICAgICAgICAgICRmb250SWQgPSAkZm9udHNbJGZvbnROYW1lXQogICAgICAgICAg"
	+ "ICBpZiAoLW5vdCAkZm9udE1hcHMuQ29udGFpbnNLZXkoJGZvbnRJZCkpIHsgY29udGludWUgfQogICAgICAgICAgICAkbWFwID0gJGZvbnRNYXBzWyRmb250SWRdCiAgICAgICAgICAgICRkZWNvZGVkID0gIiIKICAgICAgICAgICAgZm9y"
	+ "ZWFjaCAoJHN0ciBpbiBbcmVnZXhdOjpNYXRjaGVzKCR0b2suR3JvdXBzWzRdLlZhbHVlLCAiXCgoKD86XFwufFteXFwpXSkqKVwpIikpIHsKICAgICAgICAgICAgICAgICRkZWNvZGVkICs9IERlY29kZS1QZGZTdHJpbmcgJHN0ci5Hcm91"
	+ "cHNbMV0uVmFsdWUgJG1hcAogICAgICAgICAgICB9CiAgICAgICAgICAgIGlmICgkZGVjb2RlZCkgeyAkaXRlbXMgKz0gW3BzY3VzdG9tb2JqZWN0XUB7IFggPSAkeDsgWSA9IFttYXRoXTo6Um91bmQoJHkpOyBUZXh0ID0gJGRlY29kZWQg"
	+ "fSB9CiAgICAgICAgfQogICAgICAgICRpdGVtcyA9ICRpdGVtcyB8IFNvcnQtT2JqZWN0IEB7IEV4cHJlc3Npb24gPSAiWSI7IERlc2NlbmRpbmcgPSAkdHJ1ZSB9LCBAeyBFeHByZXNzaW9uID0gIlgiOyBEZXNjZW5kaW5nID0gJGZhbHNl"
	+ "IH0KICAgICAgICAkbGluZXMgPSBOZXctT2JqZWN0IFN5c3RlbS5Db2xsZWN0aW9ucy5HZW5lcmljLkxpc3Rbc3RyaW5nXQogICAgICAgICRsaW5lWSA9ICRudWxsCiAgICAgICAgJGJ1Y2tldCA9IEAoKQogICAgICAgIGZvcmVhY2ggKCRp"
	+ "dGVtIGluICRpdGVtcykgewogICAgICAgICAgICBpZiAoJG51bGwgLWVxICRsaW5lWSAtb3IgW21hdGhdOjpBYnMoJGl0ZW0uWSAtICRsaW5lWSkgLWd0IDIpIHsKICAgICAgICAgICAgICAgIGlmICgkYnVja2V0LkNvdW50KSB7CiAgICAg"
	+ "ICAgICAgICAgICAgICAgJGxpbmVzLkFkZCgoKCRidWNrZXQgfCBTb3J0LU9iamVjdCBYIHwgRm9yRWFjaC1PYmplY3QgeyAkXy5UZXh0IH0pIC1qb2luICIgIikpCiAgICAgICAgICAgICAgICB9CiAgICAgICAgICAgICAgICAkYnVja2V0"
	+ "ID0gQCgkaXRlbSkKICAgICAgICAgICAgICAgICRsaW5lWSA9ICRpdGVtLlkKICAgICAgICAgICAgfSBlbHNlIHsKICAgICAgICAgICAgICAgICRidWNrZXQgKz0gJGl0ZW0KICAgICAgICAgICAgfQogICAgICAgIH0KICAgICAgICBpZiAo"
	+ "JGJ1Y2tldC5Db3VudCkgewogICAgICAgICAgICAkbGluZXMuQWRkKCgoJGJ1Y2tldCB8IFNvcnQtT2JqZWN0IFggfCBGb3JFYWNoLU9iamVjdCB7ICRfLlRleHQgfSkgLWpvaW4gIiAiKSkKICAgICAgICB9CiAgICAgICAgaWYgKCRsaW5l"
	+ "cy5Db3VudCkgeyAkcGFnZXMuQWRkKCgkbGluZXMgLWpvaW4gImBuIikpIH0KICAgIH0KCiAgICAkdGV4dCA9ICgkcGFnZXMgLWpvaW4gImBuIikuVHJpbSgpCiAgICBpZiAoJHRleHQuTGVuZ3RoIC1sdCA0MCkgewogICAgICAgIFdyaXRl"
	+ "LUVycm9ySnNvbiAi0JIgUERGINC90LXRgiDRgtC10LrRgdGC0L7QstC+0LPQviDRgdC70L7Rjy4g0J3Rg9C20LXQvSDRhNCw0LnQuywg0LLRi9Cz0YDRg9C20LXQvdC90YvQuSDQuNC3IDHQoSwg0LAg0L3QtSDRgdC60LDQvS4iCiAgICAg"
	+ "ICAgZXhpdCAwCiAgICB9CgogICAgJHJlc3VsdCA9IENvbnZlcnQtSW52b2ljZVRleHQgJHRleHQKICAgICRqc29uID0gJHJlc3VsdCB8IENvbnZlcnRUby1Kc29uIC1EZXB0aCA2IC1Db21wcmVzcwogICAgW1N5c3RlbS5JTy5GaWxlXTo6"
	+ "V3JpdGVBbGxUZXh0KCRPdXRQYXRoLCAkanNvbiwgW1N5c3RlbS5UZXh0LlVURjhFbmNvZGluZ106Om5ldygkZmFsc2UpKQp9IGNhdGNoIHsKICAgIFdyaXRlLUVycm9ySnNvbiAoItCd0LUg0YPQtNCw0LvQvtGB0Ywg0L/RgNC+0YfQuNGC"
	+ "0LDRgtGMIFBERjogIiArICRfLkV4Y2VwdGlvbi5NZXNzYWdlKQp9Cn0KCmZ1bmN0aW9uIENvbnZlcnQtSW52b2ljZVRleHQoW3N0cmluZ10kVGV4dCkgewogICAgJG5vcm0gPSAkVGV4dCAtcmVwbGFjZSBbY2hhcl0weDAwQTAsICIgIgog"
	+ "ICAgJGlzVXBkID0gJG5vcm0gLW1hdGNoICIoP2kp0YPQvdC40LLQtdGA0YHQsNC70YzQvdGL0LlccyvQv9C10YDQtdC00LDRgtC+0YfQvdGL0LlccyvQtNC+0LrRg9C80LXQvdGCIgogICAgJGlzSW52b2ljZSA9ICRub3JtIC1tYXRjaCAi"
	+ "KD9pKdGB0YfQtdGCXHMr0L3QsFxzK9C+0L/Qu9Cw0YLRgyIKICAgICRpc0ZhY3R1cmEgPSAkbm9ybSAtbWF0Y2ggIig/aSnRgdGH0LXRgi3RhNCw0LrRgtGD0YDQsCIKICAgIGlmICgtbm90ICRpc1VwZCAtYW5kIC1ub3QgJGlzSW52b2lj"
	+ "ZSAtYW5kIC1ub3QgJGlzRmFjdHVyYSkgewogICAgICAgIHJldHVybiBAeyDQntGI0LjQsdC60LAgPSAi0K3RgtC+INC90LUg0YHRh9C10YIg0L3QsCDQvtC/0LvQsNGC0YMg0Lgg0L3QtSDQo9Cf0JQuIiB9CiAgICB9CiAgICAkd2Fybmlu"
	+ "Z3MgPSBOZXctT2JqZWN0IFN5c3RlbS5Db2xsZWN0aW9ucy5HZW5lcmljLkxpc3Rbc3RyaW5nXQogICAgJG51bWJlciA9ICIiCiAgICAkZGF0ZSA9ICIiCiAgICAkdGl0bGUgPSBbcmVnZXhdOjpNYXRjaCgkbm9ybSwgIig/aSnRgdGH0LXR"
	+ "glxzK9C90LBccyvQvtC/0LvQsNGC0YNccyvihJZccyooWzAtOUEtWmEtetCQLdCv0LAt0Y/QgdGRXC0vXSspXHMr0L7RglxzKyhcZHsxLDJ9KVxzKyhb0LAt0Y/RkV0rKVxzKyhcZHs0fSkiKQogICAgaWYgKC1ub3QgJHRpdGxlLlN1Y2Nl"
	+ "c3MpIHsKICAgICAgICAkdGl0bGUgPSBbcmVnZXhdOjpNYXRjaCgkbm9ybSwgIig/aSnRgdGH0LXRgi3RhNCw0LrRgtGD0YDQsFxzK+KEllxzKihbMC05QS1aYS160JAt0K/QsC3Rj9CB0ZFcLS9dKylccyvQvtGCXHMrKFxkezEsMn0pWy5c"
	+ "c10oXGR7MSwyfXxb0LAt0Y/RkV0rKVsuXHNdKFxkezR9KSIpCiAgICB9CiAgICBpZiAoJHRpdGxlLlN1Y2Nlc3MpIHsKICAgICAgICAkbnVtYmVyID0gJHRpdGxlLkdyb3Vwc1sxXS5WYWx1ZQogICAgICAgICRkYXRlID0gQ29udmVydC1U"
	+ "b0lzbyAkdGl0bGUuR3JvdXBzWzJdLlZhbHVlICR0aXRsZS5Hcm91cHNbM10uVmFsdWUgJHRpdGxlLkdyb3Vwc1s0XS5WYWx1ZQogICAgfQogICAgaWYgKC1ub3QgJG51bWJlcikgeyAkd2FybmluZ3MuQWRkKCLQndC+0LzQtdGAINC00L7Q"
	+ "utGD0LzQtdC90YLQsCDQvdC1INGA0LDRgdC/0L7Qt9C90LDQvS4iKSB9CiAgICBpZiAoLW5vdCAkZGF0ZSkgeyAkd2FybmluZ3MuQWRkKCLQlNCw0YLQsCDQtNC+0LrRg9C80LXQvdGC0LAg0L3QtSDRgNCw0YHQv9C+0LfQvdCw0L3QsC4i"
	+ "KSB9CgogICAgJHN1cHBsaWVyID0gR2V0LVBhcnR5ICRub3JtICIoP2kp0L/QvtGB0YLQsNCy0YnQuNC6fNC/0YDQvtC00LDQstC10YYiICIoP2kp0L/QvtC60YPQv9Cw0YLQtdC70Yx80LfQsNC60LDQt9GH0LjQuiIKICAgICRidXllciA9"
	+ "IEdldC1QYXJ0eSAkbm9ybSAiKD9pKdC/0L7QutGD0L/QsNGC0LXQu9GMfNC30LDQutCw0LfRh9C40LoiICIoP2kp0L7RgdC90L7QstCw0L3QuNC1OnzihJZccyvRgtC+0LLQsNGA0Yt80LjRgtC+0LPQvjoiCiAgICBpZiAoLW5vdCAkYnV5"
	+ "ZXIu0JjQndCdKSB7ICR3YXJuaW5ncy5BZGQoItCY0J3QnSDQv9C+0LrRg9C/0LDRgtC10LvRjyDQvdC1INC90LDQudC00LXQvS4iKSB9CgogICAgJGJhc2lzID0gIiIKICAgICRiYXNpc01hdGNoID0gW3JlZ2V4XTo6TWF0Y2goJG5vcm0s"
	+ "ICIoP2kp0L7RgdC90L7QstCw0L3QuNC1OlxzKiguKykiKQogICAgaWYgKCRiYXNpc01hdGNoLlN1Y2Nlc3MpIHsgJGJhc2lzID0gKCRiYXNpc01hdGNoLkdyb3Vwc1sxXS5WYWx1ZSAtc3BsaXQgImBuIilbMF0uVHJpbSgpIH0KICAgIGlm"
	+ "ICgtbm90ICRiYXNpcykgeyAkd2FybmluZ3MuQWRkKCLQntGB0L3QvtCy0LDQvdC40LUgKNC00L7Qs9C+0LLQvtGAKSDQvdC1INC90LDQudC00LXQvdC+LiIpIH0KCiAgICAkYmFuayA9IEdldC1CYW5rICRub3JtCiAgICAkbGluZXMgPSBH"
	+ "ZXQtTGluZXMgJG5vcm0KICAgIGlmICgkbGluZXMuQ291bnQgLWVxIDApIHsgJHdhcm5pbmdzLkFkZCgi0KHRgtGA0L7QutC4INGC0LDQsdC70LjRh9C90L7QuSDRh9Cw0YHRgtC4INC90LUg0YDQsNC30L7QsdGA0LDQvdGLLiIpIH0KCiAg"
	+ "ICAkdG90YWwgPSAwLjAKICAgICR0b3RhbE1hdGNoID0gW3JlZ2V4XTo6TWF0Y2goJG5vcm0sICIoP2kp0LLRgdC10LPQvlxzK9C6XHMr0L7Qv9C70LDRgtC1OlxzKihbXGRcc10rLFxkezJ9KSIpCiAgICBpZiAoJHRvdGFsTWF0Y2guU3Vj"
	+ "Y2VzcykgeyAkdG90YWwgPSBDb252ZXJ0LU1vbmV5ICR0b3RhbE1hdGNoLkdyb3Vwc1sxXS5WYWx1ZSB9CiAgICBlbHNlaWYgKCRsaW5lcy5Db3VudCkgeyBmb3JlYWNoICgkbGluZSBpbiAkbGluZXMpIHsgJHRvdGFsICs9ICRsaW5lLtCh"
	+ "0YPQvNC80LAgfSB9CgogICAgJHZhdFJhdGUgPSAtMQogICAgJHZhdFN1bSA9IDAuMAogICAgJHZhdE1hdGNoID0gW3JlZ2V4XTo6TWF0Y2goJG5vcm0sICIoP2kp0L3QtNGBXHMqKFxkKylccyolWzpcc10qKFtcZFxzXSssXGR7Mn0pIikK"
	+ "ICAgIGlmICgkdmF0TWF0Y2guU3VjY2VzcykgewogICAgICAgICR2YXRSYXRlID0gW2ludF0kdmF0TWF0Y2guR3JvdXBzWzFdLlZhbHVlCiAgICAgICAgJHZhdFN1bSA9IENvbnZlcnQtTW9uZXkgJHZhdE1hdGNoLkdyb3Vwc1syXS5WYWx1"
	+ "ZQogICAgfSBlbHNlaWYgKCRub3JtIC1tYXRjaCAiKD9pKdCx0LXQt1xzK9C90LTRgXzQsdC10LdccyvQvdCw0LvQvtCz0LAiKSB7CiAgICAgICAgJHZhdFJhdGUgPSAwCiAgICB9IGVsc2UgewogICAgICAgICR3YXJuaW5ncy5BZGQoItCh"
	+ "0YLQsNCy0LrQsCDQndCU0KEg0L3QtSDQvdCw0LnQtNC10L3QsC4iKQogICAgfQogICAgaWYgKCRub3JtIC1tYXRjaCAiKD9pKdC90L7QvNC10YDRgtC10LvQtdGE0L7QvdCwXHMqPSIpIHsgJHdhcm5pbmdzLkFkZCgi0JIg0LrQsNGA0YLQ"
	+ "vtGH0LrQtSDQv9C+0LrRg9C/0LDRgtC10LvRjyDQv9GD0YHRgtC+0Lkg0YLQtdC70LXRhNC+0L0uIikgfQoKICAgICRraW5kID0gItCh0YfQtdGCIgogICAgaWYgKCRpc1VwZCkgeyAka2luZCA9ICLQo9Cf0JQiIH0KICAgIHJldHVybiBA"
	+ "ewogICAgICAgINCS0LjQtCA9ICRraW5kCiAgICAgICAg0J3QvtC80LXRgCA9ICRudW1iZXIKICAgICAgICDQlNCw0YLQsCA9ICRkYXRlCiAgICAgICAg0J/QvtGB0YLQsNCy0YnQuNC6ID0gJHN1cHBsaWVyCiAgICAgICAg0J/QvtC60YPQ"
	+ "v9Cw0YLQtdC70YwgPSAkYnV5ZXIKICAgICAgICDQntGB0L3QvtCy0LDQvdC40LUgPSAkYmFzaXMKICAgICAgICDQkdCw0L3QuiA9ICRiYW5rCiAgICAgICAg0KHRgtGA0L7QutC4ID0gJGxpbmVzCiAgICAgICAg0KHRg9C80LzQsCA9IFtt"
	+ "YXRoXTo6Um91bmQoJHRvdGFsLCAyKQogICAgICAgINCh0YLQsNCy0LrQsNCd0JTQoSA9ICR2YXRSYXRlCiAgICAgICAg0KHRg9C80LzQsNCd0JTQoSA9IFttYXRoXTo6Um91bmQoJHZhdFN1bSwgMikKICAgICAgICDQodGD0LzQvNCw0JLQ"
	+ "utC70Y7Rh9Cw0LXRgtCd0JTQoSA9ICR0cnVlCiAgICAgICAg0J/RgNC10LTRg9C/0YDQtdC20LTQtdC90LjRjyA9IEAoJHdhcm5pbmdzLlRvQXJyYXkoKSkKICAgICAgICDQotC10LrRgdGCID0gJG5vcm0KICAgIH0KfQoKZnVuY3Rpb24g"
	+ "Q29udmVydC1Ub0lzbyhbc3RyaW5nXSREYXksIFtzdHJpbmddJE1vbnRoUmF3LCBbc3RyaW5nXSRZZWFyKSB7CiAgICAkbW9udGhzID0gQHsKICAgICAgICAi0Y/QvdCy0LDRgNGPIiA9IDE7ICLRhNC10LLRgNCw0LvRjyIgPSAyOyAi0LzQ"
	+ "sNGA0YLQsCIgPSAzOyAi0LDQv9GA0LXQu9GPIiA9IDQ7ICLQvNCw0Y8iID0gNTsgItC40Y7QvdGPIiA9IDYKICAgICAgICAi0LjRjtC70Y8iID0gNzsgItCw0LLQs9GD0YHRgtCwIiA9IDg7ICLRgdC10L3RgtGP0LHRgNGPIiA9IDk7ICLQ"
	+ "vtC60YLRj9Cx0YDRjyIgPSAxMDsgItC90L7Rj9Cx0YDRjyIgPSAxMTsgItC00LXQutCw0LHRgNGPIiA9IDEyCiAgICB9CiAgICAkbW9udGggPSAwCiAgICBpZiAoJE1vbnRoUmF3IC1tYXRjaCAiXlxkKyQiKSB7ICRtb250aCA9IFtpbnRd"
	+ "JE1vbnRoUmF3IH0gZWxzZSB7ICRtb250aCA9IFtpbnRdJG1vbnRoc1skTW9udGhSYXcuVG9Mb3dlcigpXSB9CiAgICAkZCA9IDA7ICR5ID0gMAogICAgW3ZvaWRdW2ludF06OlRyeVBhcnNlKCREYXksIFtyZWZdJGQpCiAgICBbdm9pZF1b"
	+ "aW50XTo6VHJ5UGFyc2UoJFllYXIsIFtyZWZdJHkpCiAgICBpZiAoJHkgLWx0IDIwMDAgLW9yICRtb250aCAtbHQgMSAtb3IgJG1vbnRoIC1ndCAxMiAtb3IgJGQgLWx0IDEgLW9yICRkIC1ndCAzMSkgeyByZXR1cm4gIiIgfQogICAgcmV0"
	+ "dXJuICJ7MDowMDAwfS17MTowMH0tezI6MDB9IiAtZiAkeSwgJG1vbnRoLCAkZAp9CgpmdW5jdGlvbiBDb252ZXJ0LU1vbmV5KFtzdHJpbmddJFJhdykgewogICAgJGNsZWFuID0gKCRSYXcgLXJlcGxhY2UgIlxzIiwgIiIpIC1yZXBsYWNl"
	+ "ICIsIiwgIi4iCiAgICAkbiA9IDAuMAogICAgW3ZvaWRdW2RvdWJsZV06OlRyeVBhcnNlKCRjbGVhbiwgW1N5c3RlbS5HbG9iYWxpemF0aW9uLk51bWJlclN0eWxlc106OkFueSwgW1N5c3RlbS5HbG9iYWxpemF0aW9uLkN1bHR1cmVJbmZv"
	+ "XTo6SW52YXJpYW50Q3VsdHVyZSwgW3JlZl0kbikKICAgIHJldHVybiBbbWF0aF06OlJvdW5kKCRuLCAyKQp9CgpmdW5jdGlvbiBHZXQtUGFydHkoW3N0cmluZ10kVGV4dCwgW3N0cmluZ10kU3RhcnRQYXR0ZXJuLCBbc3RyaW5nXSRFbmRQ"
	+ "YXR0ZXJuKSB7CiAgICAkc3RhcnQgPSBbcmVnZXhdOjpNYXRjaCgkVGV4dCwgJFN0YXJ0UGF0dGVybikKICAgIGlmICgtbm90ICRzdGFydC5TdWNjZXNzKSB7IHJldHVybiBAeyDQndCw0LjQvNC10L3QvtCy0LDQvdC40LUgPSAiIjsg0JjQ"
	+ "ndCdID0gIiI7INCa0J/QnyA9ICIiOyDQkNC00YDQtdGBID0gIiIgfSB9CiAgICAkcmVzdCA9ICRUZXh0LlN1YnN0cmluZygkc3RhcnQuSW5kZXgpCiAgICAkZW5kID0gW3JlZ2V4XTo6TWF0Y2goJHJlc3QuU3Vic3RyaW5nKDEpLCAkRW5k"
	+ "UGF0dGVybikKICAgICRibG9jayA9IGlmICgkZW5kLlN1Y2Nlc3MpIHsgJHJlc3QuU3Vic3RyaW5nKDAsICRlbmQuSW5kZXggKyAxKSB9IGVsc2UgeyAkcmVzdCB9CiAgICAkYmxvY2sgPSAoJGJsb2NrIC1yZXBsYWNlICJccysiLCAiICIp"
	+ "LlRyaW0oKQogICAgJGlubiA9IFtyZWdleF06Ok1hdGNoKCRibG9jaywgIig/aSnQmNCd0J1ccyooXGR7MTAsMTJ9KSIpCiAgICAka3BwID0gW3JlZ2V4XTo6TWF0Y2goJGJsb2NrLCAiKD9pKdCa0J/Qn1xzKihcZHs5fSkiKQogICAgJG5h"
	+ "bWUgPSBbcmVnZXhdOjpNYXRjaCgkYmxvY2ssICIoP2kpKD860L/QvtGB0YLQsNCy0YnQuNC6fNC/0YDQvtC00LDQstC10YZ80L/QvtC60YPQv9Cw0YLQtdC70Yx80LfQsNC60LDQt9GH0LjQuilccyooPzpcKFteKV0rXCk6KT9ccyooLis/"
	+ "KSxccyrQmNCd0J0iKQogICAgJGFkZHJlc3MgPSAiIgogICAgaWYgKCRrcHAuU3VjY2VzcykgewogICAgICAgICRjaHVua3MgPSBbcmVnZXhdOjpTcGxpdCgkYmxvY2ssICIoP2kp0JrQn9CfXHMqXGR7OX0sP1xzKiIpCiAgICAgICAgaWYg"
	+ "KCRjaHVua3MuQ291bnQgLWd0IDEpIHsKICAgICAgICAgICAgJGFkZHJlc3MgPSAkY2h1bmtzWzFdIC1yZXBsYWNlICIoP2kpXCjQuNGB0L/QvtC70L3QuNGC0LXQu9GMXCk6fFwo0LfQsNC60LDQt9GH0LjQulwpOiIsICIgIgogICAgICAg"
	+ "ICAgICAkYWRkcmVzcyA9ICgkYWRkcmVzcyAtcmVwbGFjZSAiKD9pKdC90L7QvNC10YDRgtC10LvQtdGE0L7QvdCwXHMqPSIsICIiIC1yZXBsYWNlICJccysiLCAiICIpLlRyaW0oKS5UcmltKCIsIikKICAgICAgICB9CiAgICB9CiAgICBy"
	+ "ZXR1cm4gQHsKICAgICAgICDQndCw0LjQvNC10L3QvtCy0LDQvdC40LUgPSAkbmFtZS5Hcm91cHNbMV0uVmFsdWUuVHJpbSgpCiAgICAgICAg0JjQndCdID0gJGlubi5Hcm91cHNbMV0uVmFsdWUKICAgICAgICDQmtCf0J8gPSAka3BwLkdy"
	+ "b3Vwc1sxXS5WYWx1ZQogICAgICAgINCQ0LTRgNC10YEgPSAkYWRkcmVzcwogICAgfQp9CgpmdW5jdGlvbiBHZXQtQmFuayhbc3RyaW5nXSRUZXh0KSB7CiAgICAkaGVhZCA9ICRUZXh0CiAgICAkY3V0ID0gW3JlZ2V4XTo6TWF0Y2goJFRl"
	+ "eHQsICIoP2kp0YHRh9C10YJccyvQvdCwXHMr0L7Qv9C70LDRgtGDfNGD0L3QuNCy0LXRgNGB0LDQu9GM0L3Ri9C5XHMr0L/QtdGA0LXQtNCw0YLQvtGH0L3Ri9C5IikKICAgIGlmICgkY3V0LlN1Y2Nlc3MpIHsgJGhlYWQgPSAkVGV4dC5T"
	+ "dWJzdHJpbmcoMCwgJGN1dC5JbmRleCkgfQogICAgJGJpayA9IFtyZWdleF06Ok1hdGNoKCRoZWFkLCAiKD9pKdCR0JjQmlxzKihcZHs5fSkiKQogICAgJGFjY291bnRzID0gW3JlZ2V4XTo6TWF0Y2hlcygkaGVhZCwgIig/aSnQodGHXC5c"
	+ "cyrihJZccyooXGR7MjB9KSIpCiAgICAkZmlyc3QgPSAoJGhlYWQgLXNwbGl0ICJgbiIpWzBdCiAgICAkYmFua05hbWUgPSAoW3JlZ2V4XTo6UmVwbGFjZSgkZmlyc3QsICIoP2kpXHMq0JHQmNCaW1xzXFNdKiQiLCAiIikpLlRyaW0oKQog"
	+ "ICAgJGNvcnIgPSBpZiAoJGFjY291bnRzLkNvdW50IC1ndCAwKSB7ICRhY2NvdW50c1swXS5Hcm91cHNbMV0uVmFsdWUgfSBlbHNlIHsgIiIgfQogICAgJGFjYyA9IGlmICgkYWNjb3VudHMuQ291bnQgLWd0IDEpIHsgJGFjY291bnRzWzFd"
	+ "Lkdyb3Vwc1sxXS5WYWx1ZSB9IGVsc2UgeyAiIiB9CiAgICByZXR1cm4gQHsg0J3QsNC40LzQtdC90L7QstCw0L3QuNC1ID0gJGJhbmtOYW1lOyDQkdCY0JogPSAkYmlrLkdyb3Vwc1sxXS5WYWx1ZTsg0JrQvtGA0YDQodGH0LXRgiA9ICRj"
	+ "b3JyOyDQoNCw0YHRh9C10YLQvdGL0LnQodGH0LXRgiA9ICRhY2MgfQp9CgpmdW5jdGlvbiBHZXQtTGluZXMoW3N0cmluZ10kVGV4dCkgewogICAgJHJlc3VsdCA9IEAoKQogICAgJHN0YXJ0ID0gW3JlZ2V4XTo6TWF0Y2goJFRleHQsICIo"
	+ "P2kp0YLQvtCy0LDRgNGLXHMqXCjRgNCw0LHQvtGC0YssXHMq0YPRgdC70YPQs9C4XCkiKQogICAgaWYgKC1ub3QgJHN0YXJ0LlN1Y2Nlc3MpIHsgcmV0dXJuICRyZXN1bHQgfQogICAgJHRhaWwgPSAkVGV4dC5TdWJzdHJpbmcoJHN0YXJ0"
	+ "LkluZGV4KQogICAgJGVuZCA9IFtyZWdleF06Ok1hdGNoKCR0YWlsLCAiKD9pbSle0LjRgtC+0LPQvjoiKQogICAgJGJsb2NrID0gaWYgKCRlbmQuU3VjY2VzcykgeyAkdGFpbC5TdWJzdHJpbmcoMCwgJGVuZC5JbmRleCkgfSBlbHNlIHsg"
	+ "JHRhaWwgfQogICAgJHJvd3MgPSAkYmxvY2sgLXNwbGl0ICJgbiIgfCBTZWxlY3QtT2JqZWN0IC1Ta2lwIDEKICAgICRjdXJyZW50ID0gJG51bGwKICAgIGZvcmVhY2ggKCRyYXcgaW4gJHJvd3MpIHsKICAgICAgICAkcm93ID0gJHJhdy5U"
	+ "cmltKCkKICAgICAgICBpZiAoLW5vdCAkcm93KSB7IGNvbnRpbnVlIH0KICAgICAgICAkbW9uZXkgPSBbcmVnZXhdOjpNYXRjaCgkcm93LCAiKFxkW1xkXHNdKlxkLFxkezJ9KVxzKyhcZFtcZFxzXSpcZCxcZHsyfSlccyokIikKICAgICAg"
	+ "ICAkaGVhZCA9IFtyZWdleF06Ok1hdGNoKCRyb3csICJeKFxkezEsM30pXHMrKC4rKSQiKQogICAgICAgIGlmICgkaGVhZC5TdWNjZXNzIC1hbmQgJG1vbmV5LlN1Y2Nlc3MgLWFuZCBbaW50XSRoZWFkLkdyb3Vwc1sxXS5WYWx1ZSAtbHQg"
	+ "NTAwKSB7CiAgICAgICAgICAgIGlmICgkbnVsbCAtbmUgJGN1cnJlbnQpIHsgJHJlc3VsdCArPSAkY3VycmVudCB9CiAgICAgICAgICAgICRxdHkgPSAxLjAKICAgICAgICAgICAgJHVuaXQgPSAi0YjRgiIKICAgICAgICAgICAgJG5hbWUg"
	+ "PSAkaGVhZC5Hcm91cHNbMl0uVmFsdWUKICAgICAgICAgICAgJHF0eU1hdGNoID0gW3JlZ2V4XTo6TWF0Y2goJHJvdywgIig/aSkoXGQrKD86Wy4sXVxkKyk/KVxzKyjRiNGCfNGD0YHQu1wuP3zRh9Cw0YEoPzrQvtCyKT980LwyfNC60L7Q"
	+ "vNC/0LtcLj8pXHMrXGRbXGRcc10qLFxkezJ9XHMrXGRbXGRcc10qLFxkezJ9XHMqJCIpCiAgICAgICAgICAgIGlmICgkcXR5TWF0Y2guU3VjY2VzcykgewogICAgICAgICAgICAgICAgJHF0eSA9IFtkb3VibGVdKCgkcXR5TWF0Y2guR3Jv"
	+ "dXBzWzFdLlZhbHVlIC1yZXBsYWNlICIsIiwgIi4iKSkKICAgICAgICAgICAgICAgICR1bml0ID0gJHF0eU1hdGNoLkdyb3Vwc1syXS5WYWx1ZQogICAgICAgICAgICAgICAgJG5hbWUgPSAkbmFtZS5TdWJzdHJpbmcoMCwgW01hdGhdOjpN"
	+ "YXgoMCwgJG5hbWUuTGVuZ3RoIC0gJHF0eU1hdGNoLkxlbmd0aCkpLlRyaW0oKQogICAgICAgICAgICB9IGVsc2UgewogICAgICAgICAgICAgICAgJG5hbWUgPSBbcmVnZXhdOjpSZXBsYWNlKCRuYW1lLCAiXHMrXGRbXGRcc10qLFxkezJ9"
	+ "XHMrXGRbXGRcc10qLFxkezJ9XHMqJCIsICIiKS5UcmltKCkKICAgICAgICAgICAgfQogICAgICAgICAgICAkY3VycmVudCA9IFtwc2N1c3RvbW9iamVjdF1AewogICAgICAgICAgICAgICAg0KHQvtC00LXRgNC20LDQvdC40LUgPSAkbmFt"
	+ "ZQogICAgICAgICAgICAgICAg0JrQvtC70LjRh9C10YHRgtCy0L4gPSAkcXR5CiAgICAgICAgICAgICAgICDQldC00LjQvdC40YbQsCA9ICR1bml0CiAgICAgICAgICAgICAgICDQptC10L3QsCA9IChDb252ZXJ0LU1vbmV5ICRtb25leS5H"
	+ "cm91cHNbMV0uVmFsdWUpCiAgICAgICAgICAgICAgICDQodGD0LzQvNCwID0gKENvbnZlcnQtTW9uZXkgJG1vbmV5Lkdyb3Vwc1syXS5WYWx1ZSkKICAgICAgICAgICAgfQogICAgICAgICAgICBjb250aW51ZQogICAgICAgIH0KICAgICAg"
	+ "ICBpZiAoJG51bGwgLW5lICRjdXJyZW50KSB7CiAgICAgICAgICAgICRjdXJyZW50LtCh0L7QtNC10YDQttCw0L3QuNC1ID0gKCgkY3VycmVudC7QodC+0LTQtdGA0LbQsNC90LjQtSArICIgIiArICRyb3cpIC1yZXBsYWNlICJccysiLCAi"
	+ "ICIpLlRyaW0oKQogICAgICAgIH0KICAgIH0KICAgIGlmICgkbnVsbCAtbmUgJGN1cnJlbnQpIHsgJHJlc3VsdCArPSAkY3VycmVudCB9CiAgICByZXR1cm4gJHJlc3VsdAp9CgpJbnZva2UtRXh0cmFjdAoK";
	Возврат ПолучитьСтрокуИзДвоичныхДанных(Base64Значение(Б64), КодировкаТекста.UTF8);

КонецФункции

Функция ТекстСкриптаДиадок()

	Б64 = "cGFyYW0oCiAgICBbUGFyYW1ldGVyKE1hbmRhdG9yeSA9ICR0cnVlKV1bc3RyaW5nXSRaaXBQYXRoLAogICAgW1BhcmFtZXRlcihNYW5kYXRvcnkgPSAkdHJ1ZSldW3N0cmluZ10kT3V0UGF0aCwKICAgIFtQYXJhbWV0ZXIoTWFuZGF0b3J5"
	+ "ID0gJHRydWUpXVtzdHJpbmddJEV4dHJhY3RTY3JpcHQKKQoKJEVycm9yQWN0aW9uUHJlZmVyZW5jZSA9ICJTdG9wIgpbU3lzdGVtLlRocmVhZGluZy5UaHJlYWRdOjpDdXJyZW50VGhyZWFkLkN1cnJlbnRDdWx0dXJlID0gW1N5c3RlbS5H"
	+ "bG9iYWxpemF0aW9uLkN1bHR1cmVJbmZvXTo6SW52YXJpYW50Q3VsdHVyZQpBZGQtVHlwZSAtQXNzZW1ibHlOYW1lIFN5c3RlbS5JTy5Db21wcmVzc2lvbgpBZGQtVHlwZSAtQXNzZW1ibHlOYW1lIFN5c3RlbS5JTy5Db21wcmVzc2lvbi5G"
	+ "aWxlU3lzdGVtCgpmdW5jdGlvbiBXcml0ZS1SZXN1bHQoW29iamVjdF0kUGF5bG9hZCkgewogICAgJGpzb24gPSAkUGF5bG9hZCB8IENvbnZlcnRUby1Kc29uIC1EZXB0aCA4IC1Db21wcmVzcwogICAgW1N5c3RlbS5JTy5GaWxlXTo6V3Jp"
	+ "dGVBbGxUZXh0KCRPdXRQYXRoLCAkanNvbiwgW1N5c3RlbS5UZXh0LlVURjhFbmNvZGluZ106Om5ldygkZmFsc2UpKQp9CgpmdW5jdGlvbiBSZXBhaXItWmlwTmFtZShbc3RyaW5nXSROYW1lKSB7CiAgICAkYmVzdCA9ICROYW1lCiAgICAk"
	+ "YmVzdFNjb3JlID0gR2V0LVJ1c3NpYW5TY29yZSAkTmFtZQogICAgZm9yZWFjaCAoJHBhZ2UgaW4gQCgxMjUxLCA0MzcpKSB7CiAgICAgICAgdHJ5IHsKICAgICAgICAgICAgJGJ5dGVzID0gW1N5c3RlbS5UZXh0LkVuY29kaW5nXTo6R2V0"
	+ "RW5jb2RpbmcoJHBhZ2UpLkdldEJ5dGVzKCROYW1lKQogICAgICAgICAgICAkZml4ZWQgPSBbU3lzdGVtLlRleHQuRW5jb2RpbmddOjpHZXRFbmNvZGluZyg4NjYpLkdldFN0cmluZygkYnl0ZXMpCiAgICAgICAgICAgICRzY29yZSA9IEdl"
	+ "dC1SdXNzaWFuU2NvcmUgJGZpeGVkCiAgICAgICAgICAgIGlmICgkc2NvcmUgLWd0ICRiZXN0U2NvcmUpIHsKICAgICAgICAgICAgICAgICRiZXN0ID0gJGZpeGVkCiAgICAgICAgICAgICAgICAkYmVzdFNjb3JlID0gJHNjb3JlCiAgICAg"
	+ "ICAgICAgIH0KICAgICAgICB9IGNhdGNoIHt9CiAgICB9CiAgICByZXR1cm4gJGJlc3QKfQoKZnVuY3Rpb24gR2V0LVJ1c3NpYW5TY29yZShbc3RyaW5nXSROYW1lKSB7CiAgICBpZiAoW3N0cmluZ106OklzTnVsbE9yRW1wdHkoJE5hbWUp"
	+ "KSB7IHJldHVybiAwIH0KICAgICRnb29kID0gW3JlZ2V4XTo6TWF0Y2hlcygkTmFtZSwgIlvQkC3Qr9CwLdGP0IHRkV0iKS5Db3VudAogICAgJGJhZCA9IFtyZWdleF06Ok1hdGNoZXMoJE5hbWUsICJb0ILQg9GT4oCe4oCm4oCg4oCh4oKs"
	+ "4oCw0InigLnQitCM0IvQj9GS4oCY4oCZ4oCc4oCd4oCi4oCT4oCU4oSi0ZnigLrRmtGc0ZvRn9CO0Z7QiNKQwqbCp9CBwqnQhMKrwqzCrtCHwrDCsdCG0ZbCtcK2wrfRkeKEltGUwrvRmNCF0ZXRl10iKS5Db3VudAogICAgcmV0dXJuICRn"
	+ "b29kIC0gKCRiYWQgKiAzKQp9CgpmdW5jdGlvbiBDb252ZXJ0LURvdERhdGUoW3N0cmluZ10kVmFsdWUpIHsKICAgIGlmICgkVmFsdWUgLW1hdGNoICJeKFxkezJ9KVwuKFxkezJ9KVwuKFxkezR9KSQiKSB7CiAgICAgICAgcmV0dXJuICJ7"
	+ "MH0tezF9LXsyfSIgLWYgJE1hdGNoZXNbM10sICRNYXRjaGVzWzJdLCAkTWF0Y2hlc1sxXQogICAgfQogICAgaWYgKCRWYWx1ZSAtbWF0Y2ggIl4oXGR7Mn0pXC4oXGR7Mn0pXC4oXGR7Mn0pJCIpIHsKICAgICAgICByZXR1cm4gIjIwezB9"
	+ "LXsxfS17Mn0iIC1mICRNYXRjaGVzWzNdLCAkTWF0Y2hlc1syXSwgJE1hdGNoZXNbMV0KICAgIH0KICAgIHJldHVybiAiIgp9CgpmdW5jdGlvbiBHZXQtRm9sZGVySW5uKFtzdHJpbmddJFBhdGgpIHsKICAgIGZvcmVhY2ggKCRwYXJ0IGlu"
	+ "ICgkUGF0aCAtc3BsaXQgIi8iKSkgewogICAgICAgIGlmICgkcGFydCAtbWF0Y2ggIl5cZHsxMH0oXGR7Mn0pPyQiKSB7IHJldHVybiAkcGFydCB9CiAgICB9CiAgICByZXR1cm4gIiIKfQoKZnVuY3Rpb24gR2V0LVBhY2tldChbc3RyaW5n"
	+ "XSRQYXRoKSB7CiAgICAkZGlyID0gW1N5c3RlbS5JTy5QYXRoXTo6R2V0RGlyZWN0b3J5TmFtZSgkUGF0aC5SZXBsYWNlKCIvIiwgIlwiKSkKICAgIGlmICgtbm90ICRkaXIpIHsgcmV0dXJuICRQYXRoIH0KICAgIHJldHVybiAoJGRpciAt"
	+ "cmVwbGFjZSAiXFwiLCAiLyIpCn0KCmZ1bmN0aW9uIEdldC1QYXJ0eU5vZGUoJE5vZGUpIHsKICAgICRlbXB0eSA9IEB7INCd0LDQuNC80LXQvdC+0LLQsNC90LjQtSA9ICIiOyDQmNCd0J0gPSAiIjsg0JrQn9CfID0gIiI7INCQ0LTRgNC1"
	+ "0YEgPSAiIiB9CiAgICBpZiAoJG51bGwgLWVxICROb2RlKSB7IHJldHVybiAkZW1wdHkgfQogICAgJHVsID0gJG51bGwKICAgICRpcCA9ICRudWxsCiAgICB0cnkgeyAkdWwgPSAkTm9kZS7QmNC00KHQsi7QodCy0K7Qm9Cj0YcgfSBjYXRj"
	+ "aCB7fQogICAgdHJ5IHsgJGlwID0gJE5vZGUu0JjQtNCh0LIu0KHQstCY0J8gfSBjYXRjaCB7fQogICAgaWYgKCR1bCkgewogICAgICAgIHJldHVybiBAewogICAgICAgICAgICDQndCw0LjQvNC10L3QvtCy0LDQvdC40LUgPSBbc3RyaW5n"
	+ "XSR1bC7QndCw0LjQvNCe0YDQswogICAgICAgICAgICDQmNCd0J0gPSBbc3RyaW5nXSR1bC7QmNCd0J3QrtCbCiAgICAgICAgICAgINCa0J/QnyA9IFtzdHJpbmddJHVsLtCa0J/QnwogICAgICAgICAgICDQkNC00YDQtdGBID0gIiIKICAg"
	+ "ICAgICB9CiAgICB9CiAgICBpZiAoJGlwKSB7CiAgICAgICAgJGZpbyA9ICRpcC7QpNCY0J4KICAgICAgICAkbmFtZSA9IChAKFtzdHJpbmddJGZpby7QpNCw0LzQuNC70LjRjywgW3N0cmluZ10kZmlvLtCY0LzRjywgW3N0cmluZ10kZmlv"
	+ "LtCe0YLRh9C10YHRgtCy0L4pIHwgV2hlcmUtT2JqZWN0IHsgJF8gfSkgLWpvaW4gIiAiCiAgICAgICAgcmV0dXJuIEB7INCd0LDQuNC80LXQvdC+0LLQsNC90LjQtSA9ICRuYW1lLlRyaW0oKTsg0JjQndCdID0gW3N0cmluZ10kaXAu0JjQ"
	+ "ndCd0KTQmzsg0JrQn9CfID0gIiI7INCQ0LTRgNC10YEgPSAiIiB9CiAgICB9CiAgICByZXR1cm4gJGVtcHR5Cn0KCmZ1bmN0aW9uIEdldC1BdHRyVGV4dCgkTm9kZSwgW3N0cmluZ10kTmFtZSkgewogICAgaWYgKCRudWxsIC1lcSAkTm9k"
	+ "ZSkgeyByZXR1cm4gIiIgfQogICAgJHZhbHVlID0gJE5vZGUuR2V0QXR0cmlidXRlKCROYW1lKQogICAgaWYgKCR2YWx1ZSkgeyByZXR1cm4gW3N0cmluZ10kdmFsdWUgfQogICAgJHByb3AgPSAkTm9kZS4kTmFtZQogICAgaWYgKCRwcm9w"
	+ "KSB7IHJldHVybiBbc3RyaW5nXSRwcm9wIH0KICAgIHJldHVybiAiIgp9CgpmdW5jdGlvbiBSZWFkLVVwZFhtbChbc3RyaW5nXSRGaWxlLCBbc3RyaW5nXSRQYWNrZXQsIFtzdHJpbmddJEZvbGRlcklubikgewogICAgJHRleHQgPSBbU3lz"
	+ "dGVtLlRleHQuRW5jb2RpbmddOjpHZXRFbmNvZGluZygxMjUxKS5HZXRTdHJpbmcoW1N5c3RlbS5JTy5GaWxlXTo6UmVhZEFsbEJ5dGVzKCRGaWxlKSkKICAgIFt4bWxdJHhtbCA9ICR0ZXh0CiAgICAkZG9jID0gJHhtbC7QpNCw0LnQuy7Q"
	+ "lNC+0LrRg9C80LXQvdGCCiAgICAkc2YgPSAkZG9jLtCh0LLQodGH0KTQsNC60YIKICAgICRzZWxsZXIgPSBHZXQtUGFydHlOb2RlICRzZi7QodCy0J/RgNC+0LQKICAgICRidXllciA9IEdldC1QYXJ0eU5vZGUgJHNmLtCh0LLQn9C+0LrR"
	+ "g9C/CiAgICAkYmFua05vZGUgPSAkbnVsbAogICAgdHJ5IHsgJGJhbmtOb2RlID0gJHNmLtCh0LLQn9GA0L7QtC7QkdCw0L3QutCg0LXQutCyIH0gY2F0Y2gge30KICAgICRiYW5rID0gQHsg0J3QsNC40LzQtdC90L7QstCw0L3QuNC1ID0g"
	+ "IiI7INCR0JjQmiA9ICIiOyDQmtC+0YDRgNCh0YfQtdGCID0gIiI7INCg0LDRgdGH0LXRgtC90YvQudCh0YfQtdGCID0gIiIgfQogICAgaWYgKCRiYW5rTm9kZSkgewogICAgICAgICRzdiA9ICRiYW5rTm9kZS7QodCy0JHQsNC90LoKICAg"
	+ "ICAgICAkYmFuayA9IEB7CiAgICAgICAgICAgINCd0LDQuNC80LXQvdC+0LLQsNC90LjQtSA9IFtzdHJpbmddJHN2LtCd0LDQuNC80JHQsNC90LoKICAgICAgICAgICAg0JHQmNCaID0gW3N0cmluZ10kc3Yu0JHQmNCaCiAgICAgICAgICAg"
	+ "INCa0L7RgNGA0KHRh9C10YIgPSBbc3RyaW5nXSRzdi7QmtC+0YDQodGH0LXRggogICAgICAgICAgICDQoNCw0YHRh9C10YLQvdGL0LnQodGH0LXRgiA9IFtzdHJpbmddJGJhbmtOb2RlLtCd0L7QvNC10YDQodGH0LXRgtCwCiAgICAgICAg"
	+ "fQogICAgfQogICAgJGxpbmVzID0gTmV3LU9iamVjdCBTeXN0ZW0uQ29sbGVjdGlvbnMuR2VuZXJpYy5MaXN0W29iamVjdF0KICAgICRnb29kcyA9IEAoKQogICAgdHJ5IHsgJGdvb2RzID0gQCgkZG9jLtCi0LDQsdC70KHRh9Ck0LDQutGC"
	+ "LtCh0LLQtdC00KLQvtCyKSB9IGNhdGNoIHt9CiAgICBmb3JlYWNoICgkcm93IGluICRnb29kcykgewogICAgICAgIGlmICgkbnVsbCAtZXEgJHJvdyAtb3IgLW5vdCAkcm93LtCd0LDQuNC80KLQvtCyKSB7IGNvbnRpbnVlIH0KICAgICAg"
	+ "ICAkcXR5ID0gMS4wCiAgICAgICAgaWYgKCRyb3cu0JrQvtC70KLQvtCyKSB7ICRxdHkgPSBbZG91YmxlXSRyb3cu0JrQvtC70KLQvtCyIH0KICAgICAgICAkZ3Jvc3MgPSAwLjAKICAgICAgICBpZiAoJHJvdy7QodGC0KLQvtCy0KPRh9Cd"
	+ "0LDQuykgeyAkZ3Jvc3MgPSBbZG91YmxlXSRyb3cu0KHRgtCi0L7QstCj0YfQndCw0LsgfQogICAgICAgICRwcmljZSA9ICRncm9zcwogICAgICAgIGlmICgkcXR5IC1uZSAwKSB7ICRwcmljZSA9IFttYXRoXTo6Um91bmQoJGdyb3NzIC8g"
	+ "JHF0eSwgMikgfQogICAgICAgICRsaW5lcy5BZGQoW3BzY3VzdG9tb2JqZWN0XUB7CiAgICAgICAgICAgINCh0L7QtNC10YDQttCw0L3QuNC1ID0gW3N0cmluZ10kcm93LtCd0LDQuNC80KLQvtCyCiAgICAgICAgICAgINCa0L7Qu9C40YfQ"
	+ "tdGB0YLQstC+ID0gJHF0eQogICAgICAgICAgICDQldC00LjQvdC40YbQsCA9IFtzdHJpbmddJHJvdy7QndCw0LjQvNCV0LTQmNC30LwKICAgICAgICAgICAg0KbQtdC90LAgPSAkcHJpY2UKICAgICAgICAgICAg0KHRg9C80LzQsCA9IFtt"
	+ "YXRoXTo6Um91bmQoJGdyb3NzLCAyKQogICAgICAgIH0pCiAgICB9CiAgICAkdG90YWwgPSAwLjAKICAgICRuZXQgPSAwLjAKICAgIHRyeSB7ICR0b3RhbCA9IFtkb3VibGVdJGRvYy7QotCw0LHQu9Ch0YfQpNCw0LrRgi7QktGB0LXQs9C+"
	+ "0J7Qv9C7LtCh0YLQotC+0LLQo9GH0J3QsNC70JLRgdC10LPQviB9IGNhdGNoIHt9CiAgICB0cnkgeyAkbmV0ID0gW2RvdWJsZV0kZG9jLtCi0LDQsdC70KHRh9Ck0LDQutGCLtCS0YHQtdCz0L7QntC/0Lsu0KHRgtCi0L7QstCR0LXQt9Cd"
	+ "0JTQodCS0YHQtdCz0L4gfSBjYXRjaCB7fQogICAgaWYgKCR0b3RhbCAtZXEgMCkgeyBmb3JlYWNoICgkbGluZSBpbiAkbGluZXMpIHsgJHRvdGFsICs9ICRsaW5lLtCh0YPQvNC80LAgfSB9CiAgICAkdmF0U3VtID0gW21hdGhdOjpSb3Vu"
	+ "ZCgkdG90YWwgLSAkbmV0LCAyKQogICAgaWYgKCR2YXRTdW0gLWx0IDApIHsgJHZhdFN1bSA9IDAgfQogICAgJHJhdGUgPSAwCiAgICAkcmF0ZVRleHQgPSAiIgogICAgaWYgKCRnb29kcy5Db3VudCAtZ3QgMCkgeyAkcmF0ZVRleHQgPSBb"
	+ "c3RyaW5nXSRnb29kc1swXS7QndCw0LvQodGCIH0KICAgIGlmICgkcmF0ZVRleHQgLW1hdGNoICIoXGQrKSIpIHsgJHJhdGUgPSBbaW50XSRNYXRjaGVzWzFdIH0KICAgICRiYXNpcyA9ICIiCiAgICAkY29udHJhY3RObyA9ICIiCiAgICAk"
	+ "Y29udHJhY3REYXRlID0gIiIKICAgICRwZXIgPSAkbnVsbAogICAgdHJ5IHsgJHBlciA9ICRkb2Mu0KHQstCf0YDQvtC00J/QtdGALtCh0LLQn9C10YAgfSBjYXRjaCB7fQogICAgaWYgKC1ub3QgJHBlcikgeyB0cnkgeyAkcGVyID0gJGRv"
	+ "Yy7QodCy0J/QtdGAIH0gY2F0Y2gge30gfQogICAgaWYgKCRwZXIpIHsKICAgICAgICAkb3NuID0gQCgkcGVyLtCe0YHQvdCf0LXRgCkgfCBTZWxlY3QtT2JqZWN0IC1GaXJzdCAxCiAgICAgICAgaWYgKCRvc24pIHsKICAgICAgICAgICAg"
	+ "JGJhc2lzID0gW3N0cmluZ10kb3NuLtCg0LXQutCy0J3QsNC40LzQlNC+0LoKICAgICAgICAgICAgJGNvbnRyYWN0Tm8gPSBbc3RyaW5nXSRvc24u0KDQtdC60LLQndC+0LzQtdGA0JTQvtC6CiAgICAgICAgICAgICRjb250cmFjdERhdGUg"
	+ "PSBDb252ZXJ0LURvdERhdGUgKFtzdHJpbmddJG9zbi7QoNC10LrQstCU0LDRgtCw0JTQvtC6KQogICAgICAgIH0KICAgIH0KICAgICRkb2NJZCA9ICIiCiAgICB0cnkgewogICAgICAgIGZvcmVhY2ggKCRpbmZvIGluIEAoJHNmLtCY0L3R"
	+ "hNCf0L7Qu9Ck0KXQljEu0KLQtdC60YHRgtCY0L3RhCkpIHsKICAgICAgICAgICAgaWYgKFtzdHJpbmddJGluZm8u0JjQtNC10L3RgtC40YQgLWVxICLQmNC00LXQvdGC0LjRhNC40LrQsNGC0L7RgNCU0L7QutGD0LzQtdC90YLQsNCe0YHQ"
	+ "vdC+0LLQsNC90LjRjyIpIHsKICAgICAgICAgICAgICAgICRkb2NJZCA9IFtzdHJpbmddJGluZm8u0JfQvdCw0YfQtdC9CiAgICAgICAgICAgIH0KICAgICAgICB9CiAgICB9IGNhdGNoIHt9CiAgICAkcGF5Tm8gPSAiIgogICAgJHBheURh"
	+ "dGUgPSAiIgogICAgdHJ5IHsKICAgICAgICAkcGF5ID0gQCgkc2Yu0KHQstCf0KDQlCkgfCBTZWxlY3QtT2JqZWN0IC1GaXJzdCAxCiAgICAgICAgaWYgKCRwYXkpIHsKICAgICAgICAgICAgJHBheU5vID0gW3N0cmluZ10kcGF5LtCd0L7Q"
	+ "vNC10YDQn9Cg0JQKICAgICAgICAgICAgJHBheURhdGUgPSBDb252ZXJ0LURvdERhdGUgKFtzdHJpbmddJHBheS7QlNCw0YLQsNCf0KDQlCkKICAgICAgICB9CiAgICB9IGNhdGNoIHt9CiAgICByZXR1cm4gW3BzY3VzdG9tb2JqZWN0XUB7"
	+ "CiAgICAgICAg0JLQuNC0ID0gItCj0J/QlCIKICAgICAgICDQmNGB0YLQvtGH0L3QuNC6ID0gIlhNTCIKICAgICAgICDQndC+0LzQtdGAID0gW3N0cmluZ10kc2Yu0J3QvtC80LXRgNCU0L7QugogICAgICAgINCU0LDRgtCwID0gKENvbnZl"
	+ "cnQtRG90RGF0ZSAoW3N0cmluZ10kc2Yu0JTQsNGC0LDQlNC+0LopKQogICAgICAgINCY0LQgPSAkZG9jSWQKICAgICAgICDQn9C+0YHRgtCw0LLRidC40LogPSAkc2VsbGVyCiAgICAgICAg0J/QvtC60YPQv9Cw0YLQtdC70YwgPSAkYnV5"
	+ "ZXIKICAgICAgICDQntGB0L3QvtCy0LDQvdC40LUgPSAkYmFzaXMKICAgICAgICDQlNC+0LPQvtCy0L7RgNCd0L7QvNC10YAgPSAkY29udHJhY3RObwogICAgICAgINCU0L7Qs9C+0LLQvtGA0JTQsNGC0LAgPSAkY29udHJhY3REYXRlCiAg"
	+ "ICAgICAg0J/Qu9Cw0YLQtdC20LrQsNCd0L7QvNC10YAgPSAkcGF5Tm8KICAgICAgICDQn9C70LDRgtC10LbQutCw0JTQsNGC0LAgPSAkcGF5RGF0ZQogICAgICAgINCR0LDQvdC6ID0gJGJhbmsKICAgICAgICDQodGC0YDQvtC60LggPSBA"
	+ "KCRsaW5lcy5Ub0FycmF5KCkpCiAgICAgICAg0KHRg9C80LzQsCA9IFttYXRoXTo6Um91bmQoJHRvdGFsLCAyKQogICAgICAgINCh0YLQsNCy0LrQsNCd0JTQoSA9ICRyYXRlCiAgICAgICAg0KHRg9C80LzQsNCd0JTQoSA9ICR2YXRTdW0K"
	+ "ICAgICAgICDQodGD0LzQvNCw0JLQutC70Y7Rh9Cw0LXRgtCd0JTQoSA9ICR0cnVlCiAgICAgICAg0J/QsNC60LXRgiA9ICRQYWNrZXQKICAgICAgICDQmNCd0J3Qn9Cw0L/QutC4ID0gJEZvbGRlcklubgogICAgICAgINCY0LzRj9Ck0LDQ"
	+ "udC70LAgPSBbU3lzdGVtLklPLlBhdGhdOjpHZXRGaWxlTmFtZSgkRmlsZSkKICAgICAgICDQn9GA0LXQtNGD0L/RgNC10LbQtNC10L3QuNGPID0gQCgpCiAgICB9Cn0KCmZ1bmN0aW9uIFJlYWQtUGRmSnNvbihbc3RyaW5nXSRGaWxlKSB7"
	+ "CiAgICAkanNvblBhdGggPSBbU3lzdGVtLklPLlBhdGhdOjpDaGFuZ2VFeHRlbnNpb24oJEZpbGUsICIuanNvbiIpCiAgICAmICRFeHRyYWN0U2NyaXB0IC1QZGZQYXRoICRGaWxlIC1PdXRQYXRoICRqc29uUGF0aAogICAgaWYgKC1ub3Qg"
	+ "KFRlc3QtUGF0aCAkanNvblBhdGgpKSB7IHJldHVybiAkbnVsbCB9CiAgICAkcmF3ID0gW1N5c3RlbS5JTy5GaWxlXTo6UmVhZEFsbFRleHQoJGpzb25QYXRoLCBbU3lzdGVtLlRleHQuVVRGOEVuY29kaW5nXTo6bmV3KCRmYWxzZSkpCiAg"
	+ "ICByZXR1cm4gJHJhdyB8IENvbnZlcnRGcm9tLUpzb24KfQoKJHdvcmsgPSBKb2luLVBhdGggKFtTeXN0ZW0uSU8uUGF0aF06OkdldFRlbXBQYXRoKCkpICgienNkaWFkb2NfIiArIFtndWlkXTo6TmV3R3VpZCgpLlRvU3RyaW5nKCJOIikp"
	+ "Ck5ldy1JdGVtIC1JdGVtVHlwZSBEaXJlY3RvcnkgLVBhdGggJHdvcmsgfCBPdXQtTnVsbAokZG9jcyA9IE5ldy1PYmplY3QgU3lzdGVtLkNvbGxlY3Rpb25zLkdlbmVyaWMuTGlzdFtvYmplY3RdCiR4bWxLZXlzID0gQHt9Cgp0cnkgewog"
	+ "ICAgJHppcCA9IFtTeXN0ZW0uSU8uQ29tcHJlc3Npb24uWmlwRmlsZV06Ok9wZW5SZWFkKCRaaXBQYXRoKQogICAgdHJ5IHsKICAgICAgICAkaW5kZXggPSAwCiAgICAgICAgZm9yZWFjaCAoJGVudHJ5IGluICR6aXAuRW50cmllcykgewog"
	+ "ICAgICAgICAgICBpZiAoLW5vdCAkZW50cnkuTmFtZSkgeyBjb250aW51ZSB9CiAgICAgICAgICAgICRmdWxsID0gUmVwYWlyLVppcE5hbWUgKCRlbnRyeS5GdWxsTmFtZS5SZXBsYWNlKCJcIiwgIi8iKSkKICAgICAgICAgICAgJGxlYWYg"
	+ "PSBbU3lzdGVtLklPLlBhdGhdOjpHZXRGaWxlTmFtZSgkZnVsbCkKICAgICAgICAgICAgJGxvdyA9ICRsZWFmLlRvTG93ZXIoKQogICAgICAgICAgICAka2VlcCA9ICRmYWxzZQogICAgICAgICAgICBpZiAoJGxvdyAtbGlrZSAib25fbnNj"
	+ "aGZkb3BwcioueG1sIikgeyAka2VlcCA9ICR0cnVlIH0KICAgICAgICAgICAgZWxzZWlmICgkbG93LkVuZHNXaXRoKCIucGRmIikgLW9yICRsb3cuRW5kc1dpdGgoIi5kb2N4IikgLW9yICRsb3cuRW5kc1dpdGgoIi5kb2MiKSkgewogICAg"
	+ "ICAgICAgICAgICAgaWYgKCRsb3cgLWxpa2UgIirQv9GA0L7RgtC+0LrQvtC7KiIpIHsgJGtlZXAgPSAkZmFsc2UgfQogICAgICAgICAgICAgICAgZWxzZWlmICgkbG93IC1saWtlICLQv9C10YfQsNGC0L3QsNGPINGE0L7RgNC80LAqIikg"
	+ "eyAka2VlcCA9ICRmYWxzZSB9CiAgICAgICAgICAgICAgICBlbHNlIHsgJGtlZXAgPSAkdHJ1ZSB9CiAgICAgICAgICAgIH0KICAgICAgICAgICAgaWYgKC1ub3QgJGtlZXApIHsgY29udGludWUgfQogICAgICAgICAgICAkaW5kZXgrKwog"
	+ "ICAgICAgICAgICAkZXh0ID0gW1N5c3RlbS5JTy5QYXRoXTo6R2V0RXh0ZW5zaW9uKCRsZWFmKQogICAgICAgICAgICAkdGFyZ2V0ID0gSm9pbi1QYXRoICR3b3JrICgiezA6MDAwMH17MX0iIC1mICRpbmRleCwgJGV4dCkKICAgICAgICAg"
	+ "ICAgJGlucHV0ID0gJGVudHJ5Lk9wZW4oKQogICAgICAgICAgICAkb3V0cHV0ID0gW1N5c3RlbS5JTy5GaWxlXTo6Q3JlYXRlKCR0YXJnZXQpCiAgICAgICAgICAgIHRyeSB7ICRpbnB1dC5Db3B5VG8oJG91dHB1dCkgfSBmaW5hbGx5IHsg"
	+ "JG91dHB1dC5EaXNwb3NlKCk7ICRpbnB1dC5EaXNwb3NlKCkgfQogICAgICAgICAgICAkcGFja2V0ID0gR2V0LVBhY2tldCAkZnVsbAogICAgICAgICAgICAkZm9sZGVySW5uID0gR2V0LUZvbGRlcklubiAkZnVsbAogICAgICAgICAgICBp"
	+ "ZiAoJGxvdyAtbGlrZSAib25fbnNjaGZkb3BwcioueG1sIikgewogICAgICAgICAgICAgICAgdHJ5IHsKICAgICAgICAgICAgICAgICAgICAkdXBkID0gUmVhZC1VcGRYbWwgJHRhcmdldCAkcGFja2V0ICRmb2xkZXJJbm4KICAgICAgICAg"
	+ "ICAgICAgICAgICAkdXBkIHwgQWRkLU1lbWJlciAtTm90ZVByb3BlcnR5TmFtZSDQmNC80Y/QpNCw0LnQu9CwIC1Ob3RlUHJvcGVydHlWYWx1ZSAkbGVhZiAtRm9yY2UKICAgICAgICAgICAgICAgICAgICAka2V5ID0gKCRwYWNrZXQgKyAi"
	+ "fCIgKyAkdXBkLtCd0L7QvNC10YApLlRvTG93ZXIoKQogICAgICAgICAgICAgICAgICAgICR4bWxLZXlzWyRrZXldID0gJHRydWUKICAgICAgICAgICAgICAgICAgICAkZG9jcy5BZGQoJHVwZCkKICAgICAgICAgICAgICAgIH0gY2F0Y2gg"
	+ "ewogICAgICAgICAgICAgICAgICAgICRkb2NzLkFkZChbcHNjdXN0b21vYmplY3RdQHsg0JLQuNC0ID0gItCf0YDQvtGH0LXQtSI7INCY0LzRj9Ck0LDQudC70LAgPSAkbGVhZjsg0J/QsNC60LXRgiA9ICRwYWNrZXQ7INCf0YDQuNGH0LjQ"
	+ "vdCwID0gJF8uRXhjZXB0aW9uLk1lc3NhZ2UgfSkKICAgICAgICAgICAgICAgIH0KICAgICAgICAgICAgICAgIGNvbnRpbnVlCiAgICAgICAgICAgIH0KICAgICAgICAgICAgJGtpbmQgPSAi0J/RgNC+0YfQtdC1IgogICAgICAgICAgICBp"
	+ "ZiAoJGxvdyAtbWF0Y2ggItGB0YfQtdGCXHMq0L3QsFxzKtC+0L/Qu9Cw0YLRg3zRgdGH0ZHRglxzKtC90LBccyrQvtC/0LvQsNGC0YMiKSB7ICRraW5kID0gItCh0YfQtdGCIiB9CiAgICAgICAgICAgIGVsc2VpZiAoJGxvdyAtbWF0Y2gg"
	+ "ItGD0L/QtHzRgdGH0LXRgi3RhNCw0LrRgtGD0YDQsHzRgdGH0ZHRgi3RhNCw0LrRgtGD0YDQsHzRgdGH0YTQtNC+0L8iKSB7ICRraW5kID0gItCj0J/QlCIgfQogICAgICAgICAgICBlbHNlaWYgKCRsb3cgLW1hdGNoICLQtNC+0LPQvtCy"
	+ "0L7RgHzQtNC+0LNfIikgeyAka2luZCA9ICLQlNC+0LPQvtCy0L7RgCIgfQogICAgICAgICAgICBlbHNlaWYgKCRsb3cgLW1hdGNoICLQsNC60YJccyrRgdCy0LXRgNC60LgiKSB7ICRraW5kID0gItCQ0LrRgtCh0LLQtdGA0LrQuCIgfQog"
	+ "ICAgICAgICAgICBlbHNlaWYgKCRsb3cgLW1hdGNoICLQtNC+0LLQtdGA0LXQvSIpIHsgJGtpbmQgPSAi0JTQvtCy0LXRgNC10L3QvdC+0YHRgtGMIiB9CiAgICAgICAgICAgIGVsc2VpZiAoJGxvdyAtbWF0Y2ggItC30LDRj9Cy0LoiKSB7"
	+ "ICRraW5kID0gItCX0LDRj9Cy0LrQsCIgfQogICAgICAgICAgICBlbHNlaWYgKCRsb3cgLW1hdGNoICLQv9C40YHRjNC8IikgeyAka2luZCA9ICLQn9C40YHRjNC80L4iIH0KICAgICAgICAgICAgZWxzZWlmICgkbG93IC1tYXRjaCAi0LDQ"
	+ "utGCIikgeyAka2luZCA9ICLQkNC60YIiIH0KCiAgICAgICAgICAgIGlmICgka2luZCAtZXEgItCh0YfQtdGCIiAtb3IgJGtpbmQgLWVxICLQo9Cf0JQiIC1vciAka2luZCAtZXEgItCQ0LrRgiIpIHsKICAgICAgICAgICAgICAgIGlmICgt"
	+ "bm90ICRsb3cuRW5kc1dpdGgoIi5wZGYiKSkgewogICAgICAgICAgICAgICAgICAgICRkb2NzLkFkZChbcHNjdXN0b21vYmplY3RdQHsg0JLQuNC0ID0gItCf0YDQvtGH0LXQtSI7INCY0LzRj9Ck0LDQudC70LAgPSAkbGVhZjsg0J/QsNC6"
	+ "0LXRgiA9ICRwYWNrZXQ7INCY0J3QndCf0LDQv9C60LggPSAkZm9sZGVySW5uOyDQn9GA0LjRh9C40L3QsCA9ICLQpNCw0LnQuyDQvdC1IFBERiwg0LIg0YPRh9C10YIg0L3QtSDQv9GA0L7QstC+0LTQuNGC0YHRjy4iIH0pCiAgICAgICAg"
	+ "ICAgICAgICAgICAgY29udGludWUKICAgICAgICAgICAgICAgIH0KICAgICAgICAgICAgICAgIHRyeSB7CiAgICAgICAgICAgICAgICAgICAgJHBhcnNlZCA9IFJlYWQtUGRmSnNvbiAkdGFyZ2V0CiAgICAgICAgICAgICAgICB9IGNhdGNo"
	+ "IHsKICAgICAgICAgICAgICAgICAgICAkcGFyc2VkID0gJG51bGwKICAgICAgICAgICAgICAgIH0KICAgICAgICAgICAgICAgIGlmICgkbnVsbCAtZXEgJHBhcnNlZCkgewogICAgICAgICAgICAgICAgICAgICRkb2NzLkFkZChbcHNjdXN0"
	+ "b21vYmplY3RdQHsg0JLQuNC0ID0gItCf0YDQvtGH0LXQtSI7INCY0LzRj9Ck0LDQudC70LAgPSAkbGVhZjsg0J/QsNC60LXRgiA9ICRwYWNrZXQ7INCf0YDQuNGH0LjQvdCwID0gIlBERiDQvdC1INGA0LDQt9C+0LHRgNCw0L0uIiB9KQog"
	+ "ICAgICAgICAgICAgICAgICAgIGNvbnRpbnVlCiAgICAgICAgICAgICAgICB9CiAgICAgICAgICAgICAgICAkcGFyc2VkIHwgQWRkLU1lbWJlciAtTm90ZVByb3BlcnR5TmFtZSDQmNGB0YLQvtGH0L3QuNC6IC1Ob3RlUHJvcGVydHlWYWx1"
	+ "ZSAiUERGIiAtRm9yY2UKICAgICAgICAgICAgICAgICRwYXJzZWQgfCBBZGQtTWVtYmVyIC1Ob3RlUHJvcGVydHlOYW1lINCf0LDQutC10YIgLU5vdGVQcm9wZXJ0eVZhbHVlICRwYWNrZXQgLUZvcmNlCiAgICAgICAgICAgICAgICAkcGFy"
	+ "c2VkIHwgQWRkLU1lbWJlciAtTm90ZVByb3BlcnR5TmFtZSDQmNCd0J3Qn9Cw0L/QutC4IC1Ob3RlUHJvcGVydHlWYWx1ZSAkZm9sZGVySW5uIC1Gb3JjZQogICAgICAgICAgICAgICAgJHBhcnNlZCB8IEFkZC1NZW1iZXIgLU5vdGVQcm9w"
	+ "ZXJ0eU5hbWUg0JjQvNGP0KTQsNC50LvQsCAtTm90ZVByb3BlcnR5VmFsdWUgJGxlYWYgLUZvcmNlCiAgICAgICAgICAgICAgICAkcGFyc2VkIHwgQWRkLU1lbWJlciAtTm90ZVByb3BlcnR5TmFtZSDQmNC0IC1Ob3RlUHJvcGVydHlWYWx1"
	+ "ZSAiIiAtRm9yY2UKICAgICAgICAgICAgICAgICRwYXJzZWQgfCBBZGQtTWVtYmVyIC1Ob3RlUHJvcGVydHlOYW1lINCf0LvQsNGC0LXQttC60LDQndC+0LzQtdGAIC1Ob3RlUHJvcGVydHlWYWx1ZSAiIiAtRm9yY2UKICAgICAgICAgICAg"
	+ "ICAgICRwYXJzZWQgfCBBZGQtTWVtYmVyIC1Ob3RlUHJvcGVydHlOYW1lINCf0LvQsNGC0LXQttC60LDQlNCw0YLQsCAtTm90ZVByb3BlcnR5VmFsdWUgIiIgLUZvcmNlCiAgICAgICAgICAgICAgICBpZiAoJHBhcnNlZC7QntGI0LjQsdC6"
	+ "0LApIHsKICAgICAgICAgICAgICAgICAgICAkcGFyc2VkLtCS0LjQtCA9ICLQn9GA0L7Rh9C10LUiCiAgICAgICAgICAgICAgICAgICAgJHBhcnNlZCB8IEFkZC1NZW1iZXIgLU5vdGVQcm9wZXJ0eU5hbWUg0J/RgNC40YfQuNC90LAgLU5v"
	+ "dGVQcm9wZXJ0eVZhbHVlIChbc3RyaW5nXSRwYXJzZWQu0J7RiNC40LHQutCwKSAtRm9yY2UKICAgICAgICAgICAgICAgIH0gZWxzZWlmICgka2luZCAtZXEgItCQ0LrRgiIgLWFuZCBbc3RyaW5nXSRwYXJzZWQu0JLQuNC0IC1uZSAi0KPQ"
	+ "n9CUIiAtYW5kIFtzdHJpbmddJHBhcnNlZC7QktC40LQgLW5lICLQodGH0LXRgiIpIHsKICAgICAgICAgICAgICAgICAgICAkcGFyc2VkLtCS0LjQtCA9ICLQn9GA0L7Rh9C10LUiCiAgICAgICAgICAgICAgICAgICAgJHBhcnNlZCB8IEFk"
	+ "ZC1NZW1iZXIgLU5vdGVQcm9wZXJ0eU5hbWUg0J/RgNC40YfQuNC90LAgLU5vdGVQcm9wZXJ0eVZhbHVlICLQkNC60YIg0LHQtdC3INCj0J/QlCDQuCDRgdGH0LXRgtCwLCDQsiDRg9GH0LXRgiDQvdC1INC/0YDQvtCy0L7QtNC40YLRgdGP"
	+ "LiIgLUZvcmNlCiAgICAgICAgICAgICAgICB9CiAgICAgICAgICAgICAgICAkZG9jcy5BZGQoJHBhcnNlZCkKICAgICAgICAgICAgICAgIGNvbnRpbnVlCiAgICAgICAgICAgIH0KCiAgICAgICAgICAgICR0aXRsZSA9IFtTeXN0ZW0uSU8u"
	+ "UGF0aF06OkdldEZpbGVOYW1lV2l0aG91dEV4dGVuc2lvbigkbGVhZikKICAgICAgICAgICAgJGRvY3MuQWRkKFtwc2N1c3RvbW9iamVjdF1AewogICAgICAgICAgICAgICAg0JLQuNC0ID0gJGtpbmQKICAgICAgICAgICAgICAgINCY0LzR"
	+ "j9Ck0LDQudC70LAgPSAkbGVhZgogICAgICAgICAgICAgICAg0J3QsNC40LzQtdC90L7QstCw0L3QuNC1ID0gJHRpdGxlCiAgICAgICAgICAgICAgICDQn9Cw0LrQtdGCID0gJHBhY2tldAogICAgICAgICAgICAgICAg0JjQndCd0J/QsNC/"
	+ "0LrQuCA9ICRmb2xkZXJJbm4KICAgICAgICAgICAgICAgINCe0YHQvdC+0LLQsNC90LjQtSA9ICR0aXRsZQogICAgICAgICAgICAgICAg0J/RgNC40YfQuNC90LAgPSAkKGlmICgka2luZCAtZXEgItCU0L7Qs9C+0LLQvtGAIikgeyAiIiB9"
	+ "IGVsc2UgeyAi0JIg0YPRh9C10YLQvdGL0LUg0LTQvtC60YPQvNC10L3RgtGLINC90LUg0L/RgNC+0LLQvtC00LjRgtGB0Y8uIiB9KQogICAgICAgICAgICB9KQogICAgICAgIH0KICAgIH0gZmluYWxseSB7CiAgICAgICAgJHppcC5EaXNw"
	+ "b3NlKCkKICAgIH0KCiAgICAkZmlsdGVyZWQgPSBOZXctT2JqZWN0IFN5c3RlbS5Db2xsZWN0aW9ucy5HZW5lcmljLkxpc3Rbb2JqZWN0XQogICAgZm9yZWFjaCAoJGRvYyBpbiAkZG9jcykgewogICAgICAgIGlmIChbc3RyaW5nXSRkb2Mu"
	+ "0JjRgdGC0L7Rh9C90LjQuiAtZXEgIlBERiIgLWFuZCBbc3RyaW5nXSRkb2Mu0JLQuNC0IC1lcSAi0KPQn9CUIikgewogICAgICAgICAgICAka2V5ID0gKFtzdHJpbmddJGRvYy7Qn9Cw0LrQtdGCICsgInwiICsgW3N0cmluZ10kZG9jLtCd"
	+ "0L7QvNC10YApLlRvTG93ZXIoKQogICAgICAgICAgICBpZiAoJHhtbEtleXMuQ29udGFpbnNLZXkoJGtleSkpIHsgY29udGludWUgfQogICAgICAgIH0KICAgICAgICAkZmlsdGVyZWQuQWRkKCRkb2MpCiAgICB9CiAgICBXcml0ZS1SZXN1"
	+ "bHQgQHsg0JTQvtC60YPQvNC10L3RgtGLID0gQCgkZmlsdGVyZWQuVG9BcnJheSgpKSB9Cn0gY2F0Y2ggewogICAgV3JpdGUtUmVzdWx0IEB7INCe0YjQuNCx0LrQsCA9ICgi0J3QtSDRg9C00LDQu9C+0YHRjCDQv9GA0L7Rh9C40YLQsNGC"
	+ "0Ywg0LDRgNGF0LjQsiDQlNC40LDQtNC+0LrQsDogIiArICRfLkV4Y2VwdGlvbi5NZXNzYWdlKSB9Cn0gZmluYWxseSB7CiAgICBpZiAoVGVzdC1QYXRoICR3b3JrKSB7IFJlbW92ZS1JdGVtICR3b3JrIC1SZWN1cnNlIC1Gb3JjZSAtRXJy"
	+ "b3JBY3Rpb24gU2lsZW50bHlDb250aW51ZSB9Cn0K"
	;

	Возврат ПолучитьСтрокуИзДвоичныхДанных(Base64Значение(Б64), КодировкаТекста.UTF8);

КонецФункции

Функция НайтиСуществующий(ИмяДокумента, НомерИзФайла, ДатаДок, Контрагент)

	Если Метаданные.Документы.Найти(ИмяДокумента) = Неопределено Тогда
		Возврат Неопределено;
	КонецЕсли;
	Если Не ЗначениеЗаполнено(Контрагент) Или Не ЗначениеЗаполнено(ДатаДок) Тогда
		Возврат Неопределено;
	КонецЕсли;

	Запрос = Новый Запрос;
	Запрос.Текст =
	"ВЫБРАТЬ
	|	Док.Ссылка КАК Ссылка,
	|	Док.Номер КАК Номер
	|ИЗ
	|	Документ." + ИмяДокумента + " КАК Док
	|ГДЕ
	|	НЕ Док.ПометкаУдаления
	|	И Док.Дата МЕЖДУ &НачалоДня И &КонецДня
	|	И Док.Контрагент = &Контрагент";
	Запрос.УстановитьПараметр("НачалоДня", НачалоДня(ДатаДок));
	Запрос.УстановитьПараметр("КонецДня", КонецДня(ДатаДок));
	Запрос.УстановитьПараметр("Контрагент", Контрагент);

	Попытка
		Выборка = Запрос.Выполнить().Выбрать();
	Исключение
		Возврат Неопределено;
	КонецПопытки;

	Пока Выборка.Следующий() Цикл
		Если НомераСовпадают(Выборка.Номер, НомерИзФайла) Тогда
			Возврат Выборка.Ссылка;
		КонецЕсли;
	КонецЦикла;

	Возврат Неопределено;

КонецФункции

Функция НомераСовпадают(НомерДокумента, НомерФайла)

	Левый = БезЛидирующихНулей(СокрЛП(Строка(НомерДокумента)));
	Правый = БезЛидирующихНулей(СокрЛП(Строка(НомерФайла)));
	Если Не ЗначениеЗаполнено(Правый) Тогда
		Возврат Ложь;
	КонецЕсли;
	Возврат Левый = Правый;

КонецФункции

Функция БезЛидирующихНулей(Текст)

	Результат = СокрЛП(Текст);
	Пока СтрДлина(Результат) > 1 И Лев(Результат, 1) = "0" Цикл
		Результат = Сред(Результат, 2);
	КонецЦикла;
	Возврат Результат;

КонецФункции

Процедура УдалитьВременные(ПутьPDF, ПутьPS, ПутьJSON)

	Попытка
		Если ЗначениеЗаполнено(ПутьPDF) Тогда
			УдалитьФайлы(ПутьPDF);
		КонецЕсли;
		Если ЗначениеЗаполнено(ПутьPS) Тогда
			УдалитьФайлы(ПутьPS);
		КонецЕсли;
		Если ЗначениеЗаполнено(ПутьJSON) Тогда
			УдалитьФайлы(ПутьJSON);
		КонецЕсли;
	Исключение
		Возврат;
	КонецПопытки;

КонецПроцедуры

Функция СоздатьСчет(Данные, ДатаДок, Организация, Контрагент, Договор, Валюта, БанковскийСчет, Ставка, Комментарий)

	Счет = Документы.СчетНаОплатуПокупателю.СоздатьДокумент();
	Счет.Дата = ДатаДок;
	Счет.Организация = Организация;
	Счет.Контрагент = Контрагент;
	УстановитьЕслиЕсть(Счет, "ДоговорКонтрагента", Договор);
	УстановитьЕслиЕсть(Счет, "ВалютаДокумента", Валюта);
	УстановитьЕслиЕсть(Счет, "СуммаВключаетНДС", Истина);
	УстановитьЕслиЕсть(Счет, "КурсВзаиморасчетов", 1);
	УстановитьЕслиЕсть(Счет, "КратностьВзаиморасчетов", 1);
	УстановитьЕслиЕсть(Счет, "Комментарий", Комментарий);
	УстановитьБанковскийСчет(Счет, БанковскийСчет);
	ЗаполнитьТабличнуюЧасть(Счет, "Товары", Данные, Ставка);
	УстановитьЕслиЕсть(Счет, "СуммаДокумента", ЧислоПоля(Данные, "Сумма", 0));
	УстановитьНомер(Счет, Данные.Номер);
	Счет.Записать();
	Возврат Счет.Ссылка;

КонецФункции

Функция ЗаполнитьСчетаУчетаРеализации(Объект)

	Если Объект = Неопределено Или Объект.Метаданные().Имя <> "РеализацияТоваровУслуг" Тогда
		Возврат Ложь;
	КонецЕсли;

	Изменено = Ложь;
	СчетРасчетов = СчетХозрасчетный("62.01");
	СчетАвансов = СчетХозрасчетный("62.02");
	СчетДоходов = СчетХозрасчетный("90.01.1");
	Если Не ЗначениеЗаполнено(СчетДоходов) Тогда
		СчетДоходов = СчетХозрасчетный("90.01");
	КонецЕсли;
	СчетНДС = СчетХозрасчетный("90.03");
	СчетРасходов = СчетХозрасчетный("90.02.1");
	Если Не ЗначениеЗаполнено(СчетРасходов) Тогда
		СчетРасходов = СчетХозрасчетный("90.02");
	КонецЕсли;
	Группа = ПерваяНоменклатурнаяГруппа();

	Если ДописатьСчетШапки(Объект, "СчетУчетаРасчетовСКонтрагентом", СчетРасчетов) Тогда
		Изменено = Истина;
	КонецЕсли;
	Если ДописатьСчетШапки(Объект, "СчетУчетаРасчетовСКонтрагентами", СчетРасчетов) Тогда
		Изменено = Истина;
	КонецЕсли;
	Если ДописатьСчетШапки(Объект, "СчетУчетаРасчетовПоАвансам", СчетАвансов) Тогда
		Изменено = Истина;
	КонецЕсли;

	ИменаТЧ = СтрРазделить("Услуги,Товары", ",");
	Для Каждого ИмяТЧ Из ИменаТЧ Цикл
		Если Объект.Метаданные().ТабличныеЧасти.Найти(ИмяТЧ) = Неопределено Тогда
			Продолжить;
		КонецЕсли;
		Для Каждого СтрокаТЧ Из Объект[ИмяТЧ] Цикл
			Если УстановитьСчетСтроки(СтрокаТЧ, "СчетДоходов", СчетДоходов) Тогда
				Изменено = Истина;
			КонецЕсли;
			Если УстановитьСчетСтроки(СтрокаТЧ, "СчетУчетаНДСПоРеализации", СчетНДС) Тогда
				Изменено = Истина;
			КонецЕсли;
			Если УстановитьСчетСтроки(СтрокаТЧ, "СчетРасходов", СчетРасходов) Тогда
				Изменено = Истина;
			КонецЕсли;
			Если УстановитьСчетСтроки(СтрокаТЧ, "Субконто", Группа) Тогда
				Изменено = Истина;
			КонецЕсли;
		КонецЦикла;
	КонецЦикла;

	Возврат Изменено;

КонецФункции

Функция ДописатьСчетШапки(Объект, Имя, Счет)

	Если Не ЗначениеЗаполнено(Счет) Или Объект.Метаданные().Реквизиты.Найти(Имя) = Неопределено Тогда
		Возврат Ложь;
	КонецЕсли;
	Если ЗначениеЗаполнено(Объект[Имя]) Тогда
		Возврат Ложь;
	КонецЕсли;
	Объект[Имя] = Счет;
	Возврат Истина;

КонецФункции

Функция УстановитьСчетСтроки(СтрокаТЧ, Имя, Значение)

	Если Не ЗначениеЗаполнено(Значение) Или Не КолонкаПуста(СтрокаТЧ, Имя) Тогда
		Возврат Ложь;
	КонецЕсли;
	Попытка
		СтрокаТЧ[Имя] = Значение;
	Исключение
		Возврат Ложь;
	КонецПопытки;
	Возврат Истина;

КонецФункции

Функция СчетХозрасчетный(Код)

	Если Метаданные.ПланыСчетов.Найти("Хозрасчетный") = Неопределено Тогда
		Возврат Неопределено;
	КонецЕсли;
	Счет = ПланыСчетов.Хозрасчетный.НайтиПоКоду(Код);
	Если ЗначениеЗаполнено(Счет) Тогда
		Возврат Счет;
	КонецЕсли;
	Возврат Неопределено;

КонецФункции

Функция ПерваяНоменклатурнаяГруппа()

	Если Метаданные.Справочники.Найти("НоменклатурныеГруппы") = Неопределено Тогда
		Возврат Неопределено;
	КонецЕсли;
	Запрос = Новый Запрос;
	Запрос.Текст =
	"ВЫБРАТЬ ПЕРВЫЕ 1
	|	Группы.Ссылка КАК Ссылка
	|ИЗ
	|	Справочник.НоменклатурныеГруппы КАК Группы
	|ГДЕ
	|	НЕ Группы.ПометкаУдаления
	|	И НЕ Группы.ЭтоГруппа
	|
	|УПОРЯДОЧИТЬ ПО
	|	Группы.Наименование";
	Попытка
		Выборка = Запрос.Выполнить().Выбрать();
	Исключение
		Возврат Неопределено;
	КонецПопытки;
	Если Выборка.Следующий() Тогда
		Возврат Выборка.Ссылка;
	КонецЕсли;
	Возврат Неопределено;

КонецФункции

Функция СоздатьРеализацию(Данные, ДатаДок, Организация, Контрагент, Договор, Валюта, БанковскийСчет, СчетСсылка, Ставка, Комментарий, Протокол)

	Реализация = Документы.РеализацияТоваровУслуг.СоздатьДокумент();
	Реализация.Дата = ДатаДок;
	Реализация.Организация = Организация;
	Реализация.Контрагент = Контрагент;
	Услуги = Ложь;
	Если ЕстьЗначениеПеречисления("ВидыОперацийРеализацияТоваров", "Услуги") Тогда
		Реализация.ВидОперации = Перечисления.ВидыОперацийРеализацияТоваров.Услуги;
		Услуги = Истина;
	КонецЕсли;
	УстановитьЕслиЕсть(Реализация, "ДоговорКонтрагента", Договор);
	УстановитьЕслиЕсть(Реализация, "ВалютаДокумента", Валюта);
	УстановитьЕслиЕсть(Реализация, "СуммаВключаетНДС", Истина);
	УстановитьЕслиЕсть(Реализация, "КурсВзаиморасчетов", 1);
	УстановитьЕслиЕсть(Реализация, "КратностьВзаиморасчетов", 1);
	УстановитьЕслиЕсть(Реализация, "Комментарий", Комментарий + " УПД, статус 1.");
	УстановитьЕслиЕсть(Реализация, "СчетНаОплатуПокупателю", СчетСсылка);
	УстановитьБанковскийСчет(Реализация, БанковскийСчет);
	ИмяТЧ = "Товары";
	Если Услуги И Реализация.Метаданные().ТабличныеЧасти.Найти("Услуги") <> Неопределено Тогда
		ИмяТЧ = "Услуги";
	КонецЕсли;
	ЗаполнитьТабличнуюЧасть(Реализация, ИмяТЧ, Данные, Ставка);
	ЗаполнитьСчетаУчетаРеализации(Реализация);
	УстановитьЕслиЕсть(Реализация, "СуммаДокумента", ЧислоПоля(Данные, "Сумма", 0));
	УстановитьНомер(Реализация, Данные.Номер);
	Попытка
		Реализация.Записать(РежимЗаписиДокумента.Проведение);
	Исключение
		Реализация.Записать(РежимЗаписиДокумента.Запись);
		Протокол.Добавить("Реализация записана без проведения: " + КраткоеПредставлениеОшибки(ИнформацияОбОшибке()));
	КонецПопытки;
	Возврат Реализация.Ссылка;

КонецФункции

Функция СоздатьСчетФактуру(Данные, ДатаДок, Организация, Контрагент, Договор, Реализация, Протокол)

	СчетФактура = Документы.СчетФактураВыданный.СоздатьДокумент();
	СчетФактура.Дата = ДатаДок;
	СчетФактура.Организация = Организация;
	СчетФактура.Контрагент = Контрагент;
	УстановитьЕслиЕсть(СчетФактура, "ДоговорКонтрагента", Договор);
	Если ЕстьЗначениеПеречисления("ВидСчетаФактурыВыставленного", "НаРеализацию") Тогда
		СчетФактура.ВидСчетаФактуры = Перечисления.ВидСчетаФактурыВыставленного.НаРеализацию;
	ИначеЕсли ЕстьЗначениеПеречисления("ВидыСчетовФактур", "НаРеализацию") Тогда
		УстановитьЕслиЕсть(СчетФактура, "ВидСчетаФактуры", Перечисления.ВидыСчетовФактур.НаРеализацию);
	КонецЕсли;
	УстановитьЕслиЕсть(СчетФактура, "КодВидаОперации", "01");
	УстановитьЕслиЕсть(СчетФактура, "ДокументОснование", Реализация);
	УстановитьЕслиЕсть(СчетФактура, "Комментарий", "УПД, статус 1. Загружено из PDF.");
	Если СчетФактура.Метаданные().ТабличныеЧасти.Найти("ДокументыОснования") <> Неопределено Тогда
		СтрокаОснования = СчетФактура.ДокументыОснования.Добавить();
		СтрокаОснования.ДокументОснование = Реализация;
	КонецЕсли;
	УстановитьНомер(СчетФактура, Данные.Номер);
	Попытка
		СчетФактура.Записать(РежимЗаписиДокумента.Проведение);
	Исключение
		СчетФактура.Записать(РежимЗаписиДокумента.Запись);
		Протокол.Добавить("Счет-фактура записан без проведения: " + КраткоеПредставлениеОшибки(ИнформацияОбОшибке()));
	КонецПопытки;
	Возврат СчетФактура.Ссылка;

КонецФункции

Процедура ЗаполнитьТабличнуюЧасть(ДокументОбъект, ИмяТЧ, Данные, Ставка)

	Если ДокументОбъект.Метаданные().ТабличныеЧасти.Найти(ИмяТЧ) = Неопределено Тогда
		ВызватьИсключение "У документа нет табличной части " + ИмяТЧ + ".";
	КонецЕсли;

	ТабличнаяЧасть = ДокументОбъект[ИмяТЧ];
	Строки = ЗначениеПоля(Данные, "Строки", Новый Массив);
	Если ТипЗнч(Строки) <> Тип("Массив") Или Строки.Количество() = 0 Тогда
		Строки = Новый Массив;
		Строки.Добавить(Новый Структура("Содержание, Количество, Единица, Цена, Сумма", "Услуги", 1, "шт", ЧислоПоля(Данные, "Сумма", 0), ЧислоПоля(Данные, "Сумма", 0)));
	КонецЕсли;

	СуммаДокумента = ЧислоПоля(Данные, "Сумма", 0);
	СуммаНДСДокумента = ЧислоПоля(Данные, "СуммаНДС", 0);
	ЕстьСодержание = ДокументОбъект.Метаданные().ТабличныеЧасти[ИмяТЧ].Реквизиты.Найти("Содержание") <> Неопределено;
	Единственная = Строки.Количество() = 1;
	Для Каждого СтрокаДанных Из Строки Цикл
		НоваяСтрока = ТабличнаяЧасть.Добавить();
		ТекстСтроки = ТекстСтрокиДокумента(СтрокаДанных);
		Номенклатура = НайтиНоменклатуру(ТекстСтроки);
		УстановитьРеквизитСтроки(НоваяСтрока, "Номенклатура", Номенклатура);
		Если ЕстьСодержание Тогда
			УстановитьРеквизитСтроки(НоваяСтрока, "Содержание", ТекстСтроки);
		КонецЕсли;
		УстановитьРеквизитСтроки(НоваяСтрока, "Количество", ЧислоПоля(СтрокаДанных, "Количество", 1));
		УстановитьРеквизитСтроки(НоваяСтрока, "Цена", ЧислоПоля(СтрокаДанных, "Цена", СуммаДокумента));
		УстановитьРеквизитСтроки(НоваяСтрока, "Сумма", ЧислоПоля(СтрокаДанных, "Сумма", СуммаДокумента));
		Если Ставка <> Неопределено Тогда
			УстановитьРеквизитСтроки(НоваяСтрока, "СтавкаНДС", Ставка);
		КонецЕсли;
		СуммаСтроки = ЧислоПоля(СтрокаДанных, "Сумма", СуммаДокумента);
		СуммаНДС = 0;
		Если Единственная Тогда
			СуммаНДС = СуммаНДСДокумента;
		ИначеЕсли СуммаДокумента <> 0 Тогда
			СуммаНДС = Окр(СуммаНДСДокумента * СуммаСтроки / СуммаДокумента, 2);
		КонецЕсли;
		УстановитьРеквизитСтроки(НоваяСтрока, "СуммаНДС", СуммаНДС);
	КонецЦикла;

КонецПроцедуры

Функция НайтиОрганизацию(ИНН)

	Запрос = Новый Запрос;
	Запрос.Текст =
	"ВЫБРАТЬ ПЕРВЫЕ 1
	|	Организации.Ссылка КАК Ссылка
	|ИЗ
	|	Справочник.Организации КАК Организации
	|ГДЕ
	|	Организации.ИНН = &ИНН
	|	И НЕ Организации.ПометкаУдаления";
	Запрос.УстановитьПараметр("ИНН", ИНН);
	Выборка = Запрос.Выполнить().Выбрать();
	Если Выборка.Следующий() Тогда
		Возврат Выборка.Ссылка;
	КонецЕсли;

	Запрос.Текст =
	"ВЫБРАТЬ ПЕРВЫЕ 1
	|	Организации.Ссылка КАК Ссылка
	|ИЗ
	|	Справочник.Организации КАК Организации
	|ГДЕ
	|	НЕ Организации.ПометкаУдаления";
	Выборка = Запрос.Выполнить().Выбрать();
	Если Выборка.Следующий() Тогда
		Возврат Выборка.Ссылка;
	КонецЕсли;

	Возврат Справочники.Организации.ПустаяСсылка();

КонецФункции

Функция НайтиИлиСоздатьКонтрагента(Покупатель)

	Запрос = Новый Запрос;
	Запрос.Текст =
	"ВЫБРАТЬ ПЕРВЫЕ 1
	|	Контрагенты.Ссылка КАК Ссылка
	|ИЗ
	|	Справочник.Контрагенты КАК Контрагенты
	|ГДЕ
	|	Контрагенты.ИНН = &ИНН
	|	И НЕ Контрагенты.ПометкаУдаления";
	Запрос.УстановитьПараметр("ИНН", Покупатель.ИНН);
	Выборка = Запрос.Выполнить().Выбрать();
	Если Выборка.Следующий() Тогда
		ДополнитьКонтрагента(Выборка.Ссылка, Покупатель);
		Возврат Выборка.Ссылка;
	КонецЕсли;

	Контрагент = Справочники.Контрагенты.СоздатьЭлемент();
	Контрагент.Наименование = Лев(СокрЛП(Покупатель.Наименование), 100);
	УстановитьЕслиЕсть(Контрагент, "НаименованиеПолное", Покупатель.Наименование);
	УстановитьЕслиЕсть(Контрагент, "ИНН", Покупатель.ИНН);
	УстановитьЕслиЕсть(Контрагент, "КПП", Покупатель.КПП);
	УстановитьЕслиЕсть(Контрагент, "Комментарий", "Создан при загрузке PDF. " + Покупатель.Адрес);
	Если СтрДлина(Покупатель.ИНН) = 12 И ЕстьЗначениеПеречисления("ЮридическоеФизическоеЛицо", "ФизическоеЛицо") Тогда
		УстановитьЕслиЕсть(Контрагент, "ЮридическоеФизическоеЛицо", Перечисления.ЮридическоеФизическоеЛицо.ФизическоеЛицо);
	ИначеЕсли ЕстьЗначениеПеречисления("ЮридическоеФизическоеЛицо", "ЮридическоеЛицо") Тогда
		УстановитьЕслиЕсть(Контрагент, "ЮридическоеФизическоеЛицо", Перечисления.ЮридическоеФизическоеЛицо.ЮридическоеЛицо);
	КонецЕсли;
	Контрагент.Записать();
	ДополнитьКонтрагента(Контрагент.Ссылка, Покупатель);
	Возврат Контрагент.Ссылка;

КонецФункции

Процедура ДополнитьКонтрагента(КонтрагентСсылка, Покупатель)

	Если Не ЗначениеЗаполнено(КонтрагентСсылка) Тогда
		Возврат;
	КонецЕсли;

	Объект = КонтрагентСсылка.ПолучитьОбъект();
	Наименование = СокрЛП(Строка(ЗначениеПоля(Покупатель, "Наименование", "")));
	Если ЗначениеЗаполнено(Наименование) Тогда
		Если Не ЗначениеЗаполнено(Объект.Наименование) Тогда
			Объект.Наименование = Лев(Наименование, 100);
		КонецЕсли;
		УстановитьЕслиПусто(Объект, "НаименованиеПолное", Наименование);
	КонецЕсли;
	УстановитьЕслиПусто(Объект, "ИНН", ЗначениеПоля(Покупатель, "ИНН", ""));
	УстановитьЕслиПусто(Объект, "КПП", ЗначениеПоля(Покупатель, "КПП", ""));
	ИНН = СокрЛП(Строка(ЗначениеПоля(Покупатель, "ИНН", "")));
	Если Объект.Метаданные().Реквизиты.Найти("ЮридическоеФизическоеЛицо") <> Неопределено
		И Не ЗначениеЗаполнено(Объект.ЮридическоеФизическоеЛицо) Тогда
		Если СтрДлина(ИНН) = 12 И ЕстьЗначениеПеречисления("ЮридическоеФизическоеЛицо", "ФизическоеЛицо") Тогда
			Объект.ЮридическоеФизическоеЛицо = Перечисления.ЮридическоеФизическоеЛицо.ФизическоеЛицо;
		ИначеЕсли ЕстьЗначениеПеречисления("ЮридическоеФизическоеЛицо", "ЮридическоеЛицо") Тогда
			Объект.ЮридическоеФизическоеЛицо = Перечисления.ЮридическоеФизическоеЛицо.ЮридическоеЛицо;
		КонецЕсли;
	КонецЕсли;

	Адрес = СокрЛП(Строка(ЗначениеПоля(Покупатель, "Адрес", "")));
	Если ЗначениеЗаполнено(Адрес) Тогда
		ДобавитьАдресКонтрагента(Объект, Адрес);
		Если Не СтрНайти(Строка(Объект.Комментарий), Адрес) Тогда
			Текст = СокрЛП(Строка(Объект.Комментарий));
			Объект.Комментарий = СокрЛП(Текст + " " + Адрес);
		КонецЕсли;
	КонецЕсли;

	Попытка
		Объект.Записать();
	Исключение
		Возврат;
	КонецПопытки;

КонецПроцедуры

Процедура ДобавитьАдресКонтрагента(Объект, Адрес)

	Если Объект.Метаданные().ТабличныеЧасти.Найти("КонтактнаяИнформация") = Неопределено Тогда
		Возврат;
	КонецЕсли;
	Для Каждого СтрокаАдреса Из Объект.КонтактнаяИнформация Цикл
		Если СтрНайти(Строка(СтрокаАдреса.Представление), Адрес) > 0 Тогда
			Возврат;
		КонецЕсли;
	КонецЦикла;

	Вид = Неопределено;
	Попытка
		Вид = Справочники.ВидыКонтактнойИнформации.ЮрАдресКонтрагента;
	Исключение
		Вид = Неопределено;
	КонецПопытки;

	СтрокаАдреса = Объект.КонтактнаяИнформация.Добавить();
	УстановитьРеквизитСтроки(СтрокаАдреса, "Представление", Адрес);
	Если ЗначениеЗаполнено(Вид) Тогда
		УстановитьРеквизитСтроки(СтрокаАдреса, "Вид", Вид);
	КонецЕсли;
	Если ЕстьЗначениеПеречисления("ТипыКонтактнойИнформации", "Адрес") Тогда
		УстановитьРеквизитСтроки(СтрокаАдреса, "Тип", Перечисления.ТипыКонтактнойИнформации.Адрес);
	КонецЕсли;

КонецПроцедуры

Функция НайтиИлиСоздатьБанковскийСчет(Владелец, ДанныеБанка)

	Номер = ТолькоЦифры(ЗначениеПоля(ДанныеБанка, "РасчетныйСчет", ""));
	Если СтрДлина(Номер) <> 20 Или Не ЗначениеЗаполнено(Владелец) Тогда
		Возврат Неопределено;
	КонецЕсли;

	Существующий = НайтиБанковскийСчет(Владелец, Номер);
	Банк = НайтиИлиСоздатьБанк(ДанныеБанка);
	Если ЗначениеЗаполнено(Существующий) Тогда
		ДополнитьБанковскийСчет(Существующий, Банк);
		Возврат Существующий;
	КонецЕсли;

	Счет = Справочники.БанковскиеСчета.СоздатьЭлемент();
	Счет.Владелец = Владелец;
	Счет.НомерСчета = Номер;
	Счет.Наименование = "р/с " + Номер;
	Если ЗначениеЗаполнено(Банк) Тогда
		УстановитьЕслиЕсть(Счет, "Банк", Банк);
	КонецЕсли;
	УстановитьЕслиЕсть(Счет, "ВалютаДенежныхСредств", НайтиВалюту());
	Если ЕстьЗначениеПеречисления("ВидыБанковскихСчетов", "Расчетный") Тогда
		УстановитьЕслиЕсть(Счет, "ВидСчета", Перечисления.ВидыБанковскихСчетов.Расчетный);
	КонецЕсли;
	Попытка
		Счет.Записать();
	Исключение
		Возврат Неопределено;
	КонецПопытки;
	Возврат Счет.Ссылка;

КонецФункции

Функция НайтиИлиСоздатьБанк(ДанныеБанка)

	Если Метаданные.Справочники.Найти("Банки") = Неопределено Тогда
		Возврат Неопределено;
	КонецЕсли;
	БИК = ТолькоЦифры(ЗначениеПоля(ДанныеБанка, "БИК", ""));
	Если СтрДлина(БИК) <> 9 Тогда
		Возврат Неопределено;
	КонецЕсли;

	Банк = Справочники.Банки.НайтиПоКоду(БИК);
	Если ЗначениеЗаполнено(Банк) Тогда
		Возврат Банк;
	КонецЕсли;

	Объект = Справочники.Банки.СоздатьЭлемент();
	Объект.Код = БИК;
	Наименование = СокрЛП(Строка(ЗначениеПоля(ДанныеБанка, "Наименование", "")));
	Объект.Наименование = ?(ЗначениеЗаполнено(Наименование), Лев(Наименование, 100), "Банк " + БИК);
	УстановитьЕслиЕсть(Объект, "КоррСчет", ТолькоЦифры(ЗначениеПоля(ДанныеБанка, "КоррСчет", "")));
	Попытка
		Объект.Записать();
	Исключение
		Возврат Неопределено;
	КонецПопытки;
	Возврат Объект.Ссылка;

КонецФункции

Процедура ДополнитьБанковскийСчет(Ссылка, Банк)

	Если Не ЗначениеЗаполнено(Ссылка) Или Не ЗначениеЗаполнено(Банк) Тогда
		Возврат;
	КонецЕсли;
	Объект = Ссылка.ПолучитьОбъект();
	Если Объект.Метаданные().Реквизиты.Найти("Банк") = Неопределено Или ЗначениеЗаполнено(Объект.Банк) Тогда
		Возврат;
	КонецЕсли;
	Объект.Банк = Банк;
	Попытка
		Объект.Записать();
	Исключение
		Возврат;
	КонецПопытки;

КонецПроцедуры

Процедура ДополнитьОрганизациюСчетом(Организация, БанковскийСчет)

	Если Не ЗначениеЗаполнено(Организация) Или Не ЗначениеЗаполнено(БанковскийСчет) Тогда
		Возврат;
	КонецЕсли;
	Объект = Организация.ПолучитьОбъект();
	Если Объект.Метаданные().Реквизиты.Найти("ОсновнойБанковскийСчет") = Неопределено Тогда
		Возврат;
	КонецЕсли;
	Если ЗначениеЗаполнено(Объект.ОсновнойБанковскийСчет) Тогда
		Возврат;
	КонецЕсли;
	Объект.ОсновнойБанковскийСчет = БанковскийСчет;
	Попытка
		Объект.Записать();
	Исключение
		Возврат;
	КонецПопытки;

КонецПроцедуры

Функция ПервыйБанковскийСчет(Владелец)

	Запрос = Новый Запрос;
	Запрос.Текст =
	"ВЫБРАТЬ ПЕРВЫЕ 1
	|	Счета.Ссылка КАК Ссылка
	|ИЗ
	|	Справочник.БанковскиеСчета КАК Счета
	|ГДЕ
	|	Счета.Владелец = &Владелец
	|	И НЕ Счета.ПометкаУдаления";
	Запрос.УстановитьПараметр("Владелец", Владелец);
	Попытка
		Выборка = Запрос.Выполнить().Выбрать();
	Исключение
		Возврат Неопределено;
	КонецПопытки;
	Если Выборка.Следующий() Тогда
		Возврат Выборка.Ссылка;
	КонецЕсли;
	Возврат Неопределено;

КонецФункции

Функция ТолькоЦифры(Значение)

	Исходный = СокрЛП(Строка(Значение));
	Результат = "";
	Для Индекс = 1 По СтрДлина(Исходный) Цикл
		Символ = Сред(Исходный, Индекс, 1);
		Если СтрНайти("0123456789", Символ) > 0 Тогда
			Результат = Результат + Символ;
		КонецЕсли;
	КонецЦикла;
	Возврат Результат;

КонецФункции

Функция НайтиИлиСоздатьДоговор(Контрагент, Организация, Основание)

	Наименование = СокрЛП(Основание);
	Если ПустаяСтрока(Наименование) Тогда
		Наименование = "Основной договор";
	КонецЕсли;

	Запрос = Новый Запрос;
	Запрос.Текст =
	"ВЫБРАТЬ ПЕРВЫЕ 1
	|	Договоры.Ссылка КАК Ссылка
	|ИЗ
	|	Справочник.ДоговорыКонтрагентов КАК Договоры
	|ГДЕ
	|	Договоры.Владелец = &Владелец
	|	И Договоры.Организация = &Организация
	|	И НЕ Договоры.ПометкаУдаления
	|	И Договоры.Наименование = &Наименование";
	Запрос.УстановитьПараметр("Владелец", Контрагент);
	Запрос.УстановитьПараметр("Организация", Организация);
	Запрос.УстановитьПараметр("Наименование", Лев(Наименование, 100));
	Выборка = Запрос.Выполнить().Выбрать();
	Если Выборка.Следующий() Тогда
		Возврат Выборка.Ссылка;
	КонецЕсли;

	Договор = Справочники.ДоговорыКонтрагентов.СоздатьЭлемент();
	Договор.Владелец = Контрагент;
	Договор.Наименование = Лев(Наименование, 100);
	Договор.Организация = Организация;
	Если ЕстьЗначениеПеречисления("ВидыДоговоровКонтрагентов", "СПокупателем") Тогда
		Договор.ВидДоговора = Перечисления.ВидыДоговоровКонтрагентов.СПокупателем;
	КонецЕсли;
	УстановитьЕслиЕсть(Договор, "ВалютаВзаиморасчетов", НайтиВалюту());
	Договор.Записать();
	Возврат Договор.Ссылка;

КонецФункции

Функция НайтиНоменклатуру(Содержание)

	Кратко = Лев(СокрЛП(Содержание), 100);
	Запрос = Новый Запрос;
	Запрос.УстановитьПараметр("Наименование", Кратко);
	Запрос.Текст =
	"ВЫБРАТЬ ПЕРВЫЕ 1
	|	Номенклатура.Ссылка КАК Ссылка
	|ИЗ
	|	Справочник.Номенклатура КАК Номенклатура
	|ГДЕ
	|	НЕ Номенклатура.ЭтоГруппа
	|	И НЕ Номенклатура.ПометкаУдаления
	|	И Номенклатура.Наименование = &Наименование";
	Выборка = Запрос.Выполнить().Выбрать();
	Если Выборка.Следующий() Тогда
		Возврат Выборка.Ссылка;
	КонецЕсли;

	Запрос.Текст =
	"ВЫБРАТЬ ПЕРВЫЕ 1
	|	Номенклатура.Ссылка КАК Ссылка
	|ИЗ
	|	Справочник.Номенклатура КАК Номенклатура
	|ГДЕ
	|	НЕ Номенклатура.ЭтоГруппа
	|	И НЕ Номенклатура.ПометкаУдаления
	|	И Номенклатура.Наименование ПОДОБНО &Маска";
	Запрос.УстановитьПараметр("Маска", "%услуг%");
	Выборка = Запрос.Выполнить().Выбрать();
	Если Выборка.Следующий() Тогда
		Возврат Выборка.Ссылка;
	КонецЕсли;

	Номенклатура = Справочники.Номенклатура.СоздатьЭлемент();
	Номенклатура.Наименование = ?(ПустаяСтрока(Кратко), "Услуги", Кратко);
	УстановитьЕслиЕсть(Номенклатура, "НаименованиеПолное", Содержание);
	УстановитьЕслиЕсть(Номенклатура, "Услуга", Истина);
	Попытка
		Номенклатура.Записать();
	Исключение
		ВызватьИсключение "Не удалось создать номенклатуру. Заведите услугу вручную и повторите загрузку. "
			+ КраткоеПредставлениеОшибки(ИнформацияОбОшибке());
	КонецПопытки;
	Возврат Номенклатура.Ссылка;

КонецФункции

Функция НайтиВалюту()

	Запрос = Новый Запрос;
	Запрос.Текст =
	"ВЫБРАТЬ ПЕРВЫЕ 1
	|	Валюты.Ссылка КАК Ссылка
	|ИЗ
	|	Справочник.Валюты КАК Валюты
	|ГДЕ
	|	Валюты.Код = ""643""";
	Выборка = Запрос.Выполнить().Выбрать();
	Если Выборка.Следующий() Тогда
		Возврат Выборка.Ссылка;
	КонецЕсли;
	Возврат Справочники.Валюты.ПустаяСсылка();

КонецФункции

Функция НайтиБанковскийСчет(Владелец, НомерСчета)

	Номер = ТолькоЦифры(НомерСчета);
	Если ПустаяСтрока(Номер) Или Не ЗначениеЗаполнено(Владелец) Тогда
		Возврат Неопределено;
	КонецЕсли;
	Запрос = Новый Запрос;
	Запрос.Текст =
	"ВЫБРАТЬ
	|	Счета.Ссылка КАК Ссылка,
	|	Счета.НомерСчета КАК НомерСчета
	|ИЗ
	|	Справочник.БанковскиеСчета КАК Счета
	|ГДЕ
	|	Счета.Владелец = &Владелец
	|	И НЕ Счета.ПометкаУдаления";
	Запрос.УстановитьПараметр("Владелец", Владелец);
	Попытка
		Выборка = Запрос.Выполнить().Выбрать();
	Исключение
		Возврат Неопределено;
	КонецПопытки;
	Пока Выборка.Следующий() Цикл
		Если ТолькоЦифры(Выборка.НомерСчета) = Номер Тогда
			Возврат Выборка.Ссылка;
		КонецЕсли;
	КонецЦикла;
	Возврат Неопределено;

КонецФункции

Функция СтавкаНДС(Процент)

	Если Процент = Неопределено Или Процент < 0 Тогда
		Возврат Неопределено;
	КонецЕсли;
	Имя = "НДС" + Формат(Процент, "ЧГ=0");
	Если Процент = 0 И ЕстьЗначениеПеречисления("СтавкиНДС", "БезНДС") Тогда
		Возврат Перечисления.СтавкиНДС.БезНДС;
	КонецЕсли;
	Если ЕстьЗначениеПеречисления("СтавкиНДС", Имя) Тогда
		Возврат Перечисления.СтавкиНДС[Имя];
	КонецЕсли;
	Возврат Неопределено;

КонецФункции

Процедура УстановитьЕслиПусто(Объект, Имя, Значение)

	Если Не ЗначениеЗаполнено(Значение) Тогда
		Возврат;
	КонецЕсли;
	Если Объект.Метаданные().Реквизиты.Найти(Имя) = Неопределено Тогда
		Возврат;
	КонецЕсли;
	Если Не ЗначениеЗаполнено(Объект[Имя]) Тогда
		Объект[Имя] = Значение;
	КонецЕсли;

КонецПроцедуры

Процедура УстановитьЕслиЕсть(Объект, Имя, Значение)

	Если Объект.Метаданные().Реквизиты.Найти(Имя) <> Неопределено И Значение <> Неопределено Тогда
		Объект[Имя] = Значение;
	КонецЕсли;

КонецПроцедуры

Процедура УстановитьРеквизитСтроки(СтрокаТЧ, Имя, Значение)

	Если Значение = Неопределено Тогда
		Возврат;
	КонецЕсли;
	Попытка
		СтрокаТЧ[Имя] = Значение;
	Исключение
		Возврат;
	КонецПопытки;

КонецПроцедуры

Функция ЗначениеПоля(Объект, Имя, ПоУмолчанию = Неопределено)

	Тип = ТипЗнч(Объект);
	Если Тип = Тип("Структура") Или Тип = Тип("ФиксированнаяСтруктура") Тогда
		Если Объект.Свойство(Имя) Тогда
			Возврат Объект[Имя];
		КонецЕсли;
		Возврат ПоУмолчанию;
	КонецЕсли;
	Если Тип = Тип("Соответствие") Или Тип = Тип("ФиксированноеСоответствие") Тогда
		Если Объект.Получить(Имя) <> Неопределено Тогда
			Возврат Объект[Имя];
		КонецЕсли;
		Возврат ПоУмолчанию;
	КонецЕсли;
	Попытка
		Возврат Объект[Имя];
	Исключение
		Возврат ПоУмолчанию;
	КонецПопытки;

КонецФункции

Функция ТекстСтрокиДокумента(СтрокаДанных)

	Если ТипЗнч(СтрокаДанных) = Тип("Строка") И ЗначениеЗаполнено(СтрокаДанных) Тогда
		Возврат СокрЛП(СтрокаДанных);
	КонецЕсли;
	Для Каждого Имя Из СтрРазделить("Содержание,Наименование,Текст", ",") Цикл
		Значение = ЗначениеПоля(СтрокаДанных, Имя, "");
		Если ЗначениеЗаполнено(Значение) И ТипЗнч(Значение) <> Тип("Булево") Тогда
			Возврат СокрЛП(Строка(Значение));
		КонецЕсли;
	КонецЦикла;
	Возврат "Услуги";

КонецФункции

Функция ЧислоПоля(Объект, Имя, ПоУмолчанию)

	Значение = ЗначениеПоля(Объект, Имя, ПоУмолчанию);
	Если ТипЗнч(Значение) = Тип("Число") Тогда
		Возврат Значение;
	КонецЕсли;
	Текст = СокрЛП(Строка(Значение));
	Текст = СтрЗаменить(Текст, " ", "");
	Текст = СтрЗаменить(Текст, ".", ",");
	Если Не ЗначениеЗаполнено(Текст) Тогда
		Возврат ПоУмолчанию;
	КонецЕсли;
	Попытка
		Возврат Число(Текст);
	Исключение
		Возврат ПоУмолчанию;
	КонецПопытки;

КонецФункции

Процедура УстановитьБанковскийСчет(Объект, БанковскийСчет)

	Если Не ЗначениеЗаполнено(БанковскийСчет) Тогда
		Возврат;
	КонецЕсли;
	// В счете покупателю поле «Банковский счет» — это реквизит СтруктурнаяЕдиница.
	УстановитьЕслиПодходит(Объект, "СтруктурнаяЕдиница", БанковскийСчет);
	УстановитьЕслиПодходит(Объект, "БанковскийСчет", БанковскийСчет);
	УстановитьЕслиПодходит(Объект, "БанковскийСчетОрганизации", БанковскийСчет);
	УстановитьЕслиПодходит(Объект, "СчетОрганизации", БанковскийСчет);

КонецПроцедуры

Функция ДополнитьСуществующийДокумент(ДокументСсылка, Данные, Организация, Контрагент, Договор, Валюта, БанковскийСчет, Ставка, Комментарий, ДокументОснование)

	Если Не ЗначениеЗаполнено(ДокументСсылка) Тогда
		Возврат "";
	КонецЕсли;

	Объект = ДокументСсылка.ПолучитьОбъект();
	Изменения = Новый Массив;
	ДописатьРеквизит(Объект, "Организация", Организация, Изменения);
	ДописатьРеквизит(Объект, "Контрагент", Контрагент, Изменения);
	ДописатьРеквизит(Объект, "ДоговорКонтрагента", Договор, Изменения);
	ДописатьРеквизит(Объект, "ВалютаДокумента", Валюта, Изменения);
	ДописатьРеквизит(Объект, "СчетНаОплатуПокупателю", ДокументОснование, Изменения);
	ДописатьРеквизит(Объект, "ДокументОснование", ДокументОснование, Изменения);
	СуммаДокумента = ЧислоПоля(Данные, "Сумма", 0);
	Если СуммаДокумента <> 0 Тогда
		ДописатьРеквизит(Объект, "СуммаДокумента", СуммаДокумента, Изменения);
	КонецЕсли;
	ДописатьРеквизит(Объект, "КурсВзаиморасчетов", 1, Изменения);
	ДописатьРеквизит(Объект, "КратностьВзаиморасчетов", 1, Изменения);
	ДописатьРеквизит(Объект, "Комментарий", Комментарий, Изменения);
	Если БанковскийСчетДокументаПуст(Объект) И ЗначениеЗаполнено(БанковскийСчет) Тогда
		УстановитьБанковскийСчет(Объект, БанковскийСчет);
		Если Не БанковскийСчетДокументаПуст(Объект) Тогда
			Изменения.Добавить("банковский счет");
		КонецЕсли;
	КонецЕсли;
	ДописатьТабличныеЧасти(Объект, Данные, Ставка, Изменения);
	ДописатьОснованиеСчетаФактуры(Объект, ДокументОснование, Изменения);
	Если Объект.Метаданные().Имя = "РеализацияТоваровУслуг" И ЗаполнитьСчетаУчетаРеализации(Объект) Тогда
		Изменения.Добавить("счета учета");
	КонецЕсли;

	Если Изменения.Количество() = 0 И Объект.Проведен Тогда
		Возврат "";
	КонецЕсли;

	МожноПроводить = Объект.Метаданные().Проведение = Метаданные.СвойстваОбъектов.Проведение.Разрешить;
	Попытка
		Если МожноПроводить Тогда
			Объект.Записать(РежимЗаписиДокумента.Проведение);
		Иначе
			Объект.Записать(РежимЗаписиДокумента.Запись);
		КонецЕсли;
	Исключение
		ТекстОшибки = КраткоеПредставлениеОшибки(ИнформацияОбОшибке());
		Попытка
			Объект.Записать(РежимЗаписиДокумента.Запись);
		Исключение
			Возврат "не удалось обновить (" + СтрСоединить(Изменения, ", ") + "): " + КраткоеПредставлениеОшибки(ИнформацияОбОшибке());
		КонецПопытки;
		Возврат "записано без проведения: " + ТекстОшибки;
	КонецПопытки;

	Возврат "дополнено: " + СтрСоединить(Изменения, ", ");

КонецФункции

Процедура ДописатьРеквизит(Объект, Имя, Значение, Изменения)

	Если Не ЗначениеЗаполнено(Значение) Тогда
		Возврат;
	КонецЕсли;
	Реквизит = Объект.Метаданные().Реквизиты.Найти(Имя);
	Если Реквизит = Неопределено Или Не Реквизит.Тип.СодержитТип(ТипЗнч(Значение)) Тогда
		Возврат;
	КонецЕсли;
	Если ЗначениеЗаполнено(Объект[Имя]) Тогда
		Возврат;
	КонецЕсли;
	Объект[Имя] = Значение;
	Изменения.Добавить(Имя);

КонецПроцедуры

Процедура ДописатьТабличныеЧасти(Объект, Данные, Ставка, Изменения)

	ЕстьТовары = Объект.Метаданные().ТабличныеЧасти.Найти("Товары") <> Неопределено;
	ЕстьУслуги = Объект.Метаданные().ТабличныеЧасти.Найти("Услуги") <> Неопределено;
	Если Не ЕстьТовары И Не ЕстьУслуги Тогда
		Возврат;
	КонецЕсли;

	ИмяЗаполненной = "";
	Если ЕстьУслуги И Объект.Услуги.Количество() > 0 Тогда
		ИмяЗаполненной = "Услуги";
	ИначеЕсли ЕстьТовары И Объект.Товары.Количество() > 0 Тогда
		ИмяЗаполненной = "Товары";
	КонецЕсли;

	Если Не ЗначениеЗаполнено(ИмяЗаполненной) Тогда
		ИмяТЧ = "Товары";
		Если ЕстьУслуги И Не ЕстьТовары Тогда
			ИмяТЧ = "Услуги";
		ИначеЕсли ЕстьУслуги И Объект.Метаданные().Реквизиты.Найти("ВидОперации") <> Неопределено Тогда
			Если Объект.ВидОперации = Перечисления.ВидыОперацийРеализацияТоваров.Услуги Тогда
				ИмяТЧ = "Услуги";
			КонецЕсли;
		КонецЕсли;
		Если Объект.Метаданные().ТабличныеЧасти.Найти(ИмяТЧ) = Неопределено Тогда
			Возврат;
		КонецЕсли;
		ЗаполнитьТабличнуюЧасть(Объект, ИмяТЧ, Данные, Ставка);
		Если Объект[ИмяТЧ].Количество() > 0 Тогда
			Изменения.Добавить("строки " + ИмяТЧ);
		КонецЕсли;
		Возврат;
	КонецЕсли;

	Если ДописатьПустыеЯчейки(Объект[ИмяЗаполненной], Данные, Ставка) Тогда
		Изменения.Добавить("пустые ячейки " + ИмяЗаполненной);
	КонецЕсли;

КонецПроцедуры

Функция ДописатьПустыеЯчейки(ТабличнаяЧасть, Данные, Ставка)

	Строки = ЗначениеПоля(Данные, "Строки", Новый Массив);
	Если ТипЗнч(Строки) <> Тип("Массив") Или Строки.Количество() = 0 Тогда
		Возврат Ложь;
	КонецЕсли;

	Изменено = Ложь;
	Индекс = 0;
	Для Каждого СтрокаТЧ Из ТабличнаяЧасть Цикл
		Если Индекс >= Строки.Количество() Тогда
			Прервать;
		КонецЕсли;
		СтрокаДанных = Строки[Индекс];
		Индекс = Индекс + 1;
		ТекстСтроки = ТекстСтрокиДокумента(СтрокаДанных);
		Номенклатура = Неопределено;
		Если КолонкаПуста(СтрокаТЧ, "Номенклатура") И ЗначениеЗаполнено(ТекстСтроки) Тогда
			Номенклатура = НайтиНоменклатуру(ТекстСтроки);
			УстановитьРеквизитСтроки(СтрокаТЧ, "Номенклатура", Номенклатура);
			Изменено = Истина;
		КонецЕсли;
		Если КолонкаПуста(СтрокаТЧ, "Содержание") И ЗначениеЗаполнено(ТекстСтроки) И ТекстСтроки <> "Услуги" Тогда
			УстановитьРеквизитСтроки(СтрокаТЧ, "Содержание", ТекстСтроки);
			Изменено = Истина;
		КонецЕсли;
		Количество = ЧислоПоля(СтрокаДанных, "Количество", 0);
		Если КолонкаПуста(СтрокаТЧ, "Количество") И Количество <> 0 Тогда
			УстановитьРеквизитСтроки(СтрокаТЧ, "Количество", Количество);
			Изменено = Истина;
		КонецЕсли;
		Цена = ЧислоПоля(СтрокаДанных, "Цена", 0);
		Если КолонкаПуста(СтрокаТЧ, "Цена") И Цена <> 0 Тогда
			УстановитьРеквизитСтроки(СтрокаТЧ, "Цена", Цена);
			Изменено = Истина;
		КонецЕсли;
		СуммаСтроки = ЧислоПоля(СтрокаДанных, "Сумма", 0);
		Если КолонкаПуста(СтрокаТЧ, "Сумма") И СуммаСтроки <> 0 Тогда
			УстановитьРеквизитСтроки(СтрокаТЧ, "Сумма", СуммаСтроки);
			Изменено = Истина;
		КонецЕсли;
		Если Ставка <> Неопределено И КолонкаПуста(СтрокаТЧ, "СтавкаНДС") Тогда
			УстановитьРеквизитСтроки(СтрокаТЧ, "СтавкаНДС", Ставка);
			Изменено = Истина;
		КонецЕсли;
		СуммаНДС = ЧислоПоля(Данные, "СуммаНДС", 0);
		Если Строки.Количество() > 1 И ЧислоПоля(Данные, "Сумма", 0) <> 0 Тогда
			СуммаНДС = Окр(СуммаНДС * СуммаСтроки / ЧислоПоля(Данные, "Сумма", 0), 2);
		КонецЕсли;
		Если КолонкаПуста(СтрокаТЧ, "СуммаНДС") И СуммаНДС <> 0 Тогда
			УстановитьРеквизитСтроки(СтрокаТЧ, "СуммаНДС", СуммаНДС);
			Изменено = Истина;
		КонецЕсли;
	КонецЦикла;
	Возврат Изменено;

КонецФункции

Функция КолонкаПуста(СтрокаТЧ, Имя)

	Попытка
		Возврат Не ЗначениеЗаполнено(СтрокаТЧ[Имя]);
	Исключение
		Возврат Ложь;
	КонецПопытки;

КонецФункции

Процедура ДописатьОснованиеСчетаФактуры(Объект, ДокументОснование, Изменения)

	Если Не ЗначениеЗаполнено(ДокументОснование) Тогда
		Возврат;
	КонецЕсли;
	Если Объект.Метаданные().ТабличныеЧасти.Найти("ДокументыОснования") = Неопределено Тогда
		Возврат;
	КонецЕсли;
	Для Каждого СтрокаОснования Из Объект.ДокументыОснования Цикл
		Если СтрокаОснования.ДокументОснование = ДокументОснование Тогда
			Возврат;
		КонецЕсли;
	КонецЦикла;
	Если Объект.ДокументыОснования.Количество() > 0 Тогда
		Возврат;
	КонецЕсли;
	СтрокаОснования = Объект.ДокументыОснования.Добавить();
	СтрокаОснования.ДокументОснование = ДокументОснование;
	Изменения.Добавить("основание");

КонецПроцедуры

Функция НайтиСчетФактуру(Реализация)

	Запрос = Новый Запрос;
	Запрос.УстановитьПараметр("Основание", Реализация);
	Запрос.Текст =
	"ВЫБРАТЬ ПЕРВЫЕ 1
	|	Основания.Ссылка КАК Ссылка
	|ИЗ
	|	Документ.СчетФактураВыданный.ДокументыОснования КАК Основания
	|ГДЕ
	|	Основания.ДокументОснование = &Основание
	|	И НЕ Основания.Ссылка.ПометкаУдаления";
	Попытка
		Выборка = Запрос.Выполнить().Выбрать();
		Если Выборка.Следующий() Тогда
			Возврат Выборка.Ссылка;
		КонецЕсли;
	Исключение
		Возврат Документы.СчетФактураВыданный.ПустаяСсылка();
	КонецПопытки;
	Возврат Документы.СчетФактураВыданный.ПустаяСсылка();

КонецФункции

Функция ДописатьБанковскийСчет(ДокументСсылка, БанковскийСчет)

	Если Не ЗначениеЗаполнено(ДокументСсылка) Или Не ЗначениеЗаполнено(БанковскийСчет) Тогда
		Возврат Ложь;
	КонецЕсли;
	Объект = ДокументСсылка.ПолучитьОбъект();
	Если Не БанковскийСчетДокументаПуст(Объект) Тогда
		Возврат Ложь;
	КонецЕсли;
	УстановитьБанковскийСчет(Объект, БанковскийСчет);
	Если БанковскийСчетДокументаПуст(Объект) Тогда
		Возврат Ложь;
	КонецЕсли;
	Попытка
		Если Объект.Проведен Тогда
			Объект.Записать(РежимЗаписиДокумента.Проведение);
		Иначе
			Объект.Записать(РежимЗаписиДокумента.Запись);
		КонецЕсли;
	Исключение
		Попытка
			Объект.Записать(РежимЗаписиДокумента.Запись);
		Исключение
			Возврат Ложь;
		КонецПопытки;
	КонецПопытки;
	Возврат Истина;

КонецФункции

Функция БанковскийСчетДокументаПуст(Объект)

	Имена = СтрРазделить("СтруктурнаяЕдиница,БанковскийСчет,БанковскийСчетОрганизации,СчетОрганизации", ",");
	Для Каждого Имя Из Имена Цикл
		Реквизит = Объект.Метаданные().Реквизиты.Найти(Имя);
		Если Реквизит = Неопределено Тогда
			Продолжить;
		КонецЕсли;
		Если Не Реквизит.Тип.СодержитТип(Тип("СправочникСсылка.БанковскиеСчета")) Тогда
			Продолжить;
		КонецЕсли;
		Если ЗначениеЗаполнено(Объект[Имя]) Тогда
			Возврат Ложь;
		КонецЕсли;
	КонецЦикла;
	Возврат Истина;

КонецФункции

Функция ОсновнойСчетОрганизации(Организация)

	Запрос = Новый Запрос;
	Запрос.Текст =
	"ВЫБРАТЬ ПЕРВЫЕ 1
	|	Организации.ОсновнойБанковскийСчет КАК Счет
	|ИЗ
	|	Справочник.Организации КАК Организации
	|ГДЕ
	|	Организации.Ссылка = &Ссылка";
	Запрос.УстановитьПараметр("Ссылка", Организация);
	Попытка
		Выборка = Запрос.Выполнить().Выбрать();
	Исключение
		Возврат Неопределено;
	КонецПопытки;
	Если Выборка.Следующий() И ЗначениеЗаполнено(Выборка.Счет) Тогда
		Возврат Выборка.Счет;
	КонецЕсли;
	Возврат Неопределено;

КонецФункции

Процедура УстановитьЕслиПодходит(Объект, Имя, Значение)

	Реквизит = Объект.Метаданные().Реквизиты.Найти(Имя);
	Если Реквизит = Неопределено Или Не ЗначениеЗаполнено(Значение) Тогда
		Возврат;
	КонецЕсли;
	Если Не Реквизит.Тип.СодержитТип(ТипЗнч(Значение)) Тогда
		Возврат;
	КонецЕсли;
	Если Не ЗначениеЗаполнено(Объект[Имя]) Тогда
		Объект[Имя] = Значение;
	КонецЕсли;

КонецПроцедуры

Процедура УстановитьНомер(Объект, НомерИзФайла)

	Объект.УстановитьНовыйНомер();
	Номер = СокрЛП(НомерИзФайла);
	Длина = Объект.Метаданные().ДлинаНомера;
	Если ЗначениеЗаполнено(Номер) И СтрДлина(Номер) <= Длина Тогда
		Объект.Номер = Номер;
	КонецЕсли;

КонецПроцедуры

Функция ДатаИзСтроки(Значение)

	Если ТипЗнч(Значение) = Тип("Дата") Тогда
		Возврат Значение;
	КонецЕсли;
	Текст = СокрЛП(Строка(Значение));
	Части = СтрРазделить(Текст, "-");
	Если Части.Количество() <> 3 Тогда
		Возврат Неопределено;
	КонецЕсли;
	Возврат Дата(Число(Части[0]), Число(Части[1]), Число(Части[2]));

КонецФункции

Функция ЕстьЗначениеПеречисления(ИмяПеречисления, ИмяЗначения)

	МетаПеречисления = Метаданные.Перечисления.Найти(ИмяПеречисления);
	Если МетаПеречисления = Неопределено Тогда
		Возврат Ложь;
	КонецЕсли;
	Возврат МетаПеречисления.ЗначенияПеречисления.Найти(ИмяЗначения) <> Неопределено;

КонецФункции

Функция Экранировать(Текст)

	Возврат СтрЗаменить(СтрЗаменить(Текст, "\", "\\"), """", "'");

КонецФункции

#КонецОбласти
