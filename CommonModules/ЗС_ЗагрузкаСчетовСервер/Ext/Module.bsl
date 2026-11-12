
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
		ДатаДок = ДатаИзСтроки(ДатаИзИмениФайла(ЗначениеПоля(Данные, "ИмяФайла", "")));
	КонецЕсли;
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
	Протокол.Вставить(0, "Архив Диадок. Создано пакетов: " + Строка(Создано)
		+ ", уже было или не проводится: " + Строка(Пропущено) + ".");
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

	Б64 = "cGFyYW0oCiAgICBbUGFyYW1ldGVyKE1hbmRhdG9yeSA9ICR0cnVlKV1bc3RyaW5nXSRQZGZQYXRoLAogICAgW1BhcmFtZXRlcihNYW5kYXRvcnkgPSAkdHJ1ZSldW3N0cmluZ10kT3V0UGF0aCwKICAgIFtzdHJpbmddJFRpdGxlID0gIiIK"
	+ "KQoKJEVycm9yQWN0aW9uUHJlZmVyZW5jZSA9ICJTdG9wIgpBZGQtVHlwZSAtQXNzZW1ibHlOYW1lIFN5c3RlbS5JTy5Db21wcmVzc2lvbgoKZnVuY3Rpb24gV3JpdGUtRXJyb3JKc29uKFtzdHJpbmddJE1lc3NhZ2UpIHsKICAgICRwYXls"
	+ "b2FkID0gQHsg0J7RiNC40LHQutCwID0gJE1lc3NhZ2UgfSB8IENvbnZlcnRUby1Kc29uIC1Db21wcmVzcwogICAgW1N5c3RlbS5JTy5GaWxlXTo6V3JpdGVBbGxUZXh0KCRPdXRQYXRoLCAkcGF5bG9hZCwgW1N5c3RlbS5UZXh0LlVURjhF"
	+ "bmNvZGluZ106Om5ldygkZmFsc2UpKQp9CgpmdW5jdGlvbiBBd2FpdC1XaW5SVCgkT3BlcmF0aW9uLCBbVHlwZV0kUmVzdWx0VHlwZSkgewogICAgJG1ldGhvZCA9IChbU3lzdGVtLldpbmRvd3NSdW50aW1lU3lzdGVtRXh0ZW5zaW9uc10u"
	+ "R2V0TWV0aG9kcygpIHwgV2hlcmUtT2JqZWN0IHsKICAgICAgICAkXy5OYW1lIC1lcSAiQXNUYXNrIiAtYW5kICRfLklzR2VuZXJpY01ldGhvZCAtYW5kICRfLkdldFBhcmFtZXRlcnMoKS5Db3VudCAtZXEgMSAtYW5kICRfLkdldFBhcmFt"
	+ "ZXRlcnMoKVswXS5QYXJhbWV0ZXJUeXBlLk5hbWUgLWVxICJJQXN5bmNPcGVyYXRpb25gYDEiCiAgICB9IHwgU2VsZWN0LU9iamVjdCAtRmlyc3QgMSkKICAgICR0YXNrID0gJG1ldGhvZC5NYWtlR2VuZXJpY01ldGhvZCgkUmVzdWx0VHlw"
	+ "ZSkuSW52b2tlKCRudWxsLCBAKCRPcGVyYXRpb24pKQogICAgJHRhc2suV2FpdCgpIHwgT3V0LU51bGwKICAgIHJldHVybiAkdGFzay5SZXN1bHQKfQoKZnVuY3Rpb24gQXdhaXQtV2luUlRBY3Rpb24oJEFjdGlvbikgewogICAgJG1ldGhv"
	+ "ZCA9IChbU3lzdGVtLldpbmRvd3NSdW50aW1lU3lzdGVtRXh0ZW5zaW9uc10uR2V0TWV0aG9kcygpIHwgV2hlcmUtT2JqZWN0IHsKICAgICAgICAkXy5OYW1lIC1lcSAiQXNUYXNrIiAtYW5kIC1ub3QgJF8uSXNHZW5lcmljTWV0aG9kIC1h"
	+ "bmQgJF8uR2V0UGFyYW1ldGVycygpLkNvdW50IC1lcSAxIC1hbmQgJF8uR2V0UGFyYW1ldGVycygpWzBdLlBhcmFtZXRlclR5cGUuTmFtZSAtZXEgIklBc3luY0FjdGlvbiIKICAgIH0gfCBTZWxlY3QtT2JqZWN0IC1GaXJzdCAxKQogICAg"
	+ "JHRhc2sgPSAkbWV0aG9kLkludm9rZSgkbnVsbCwgQCgkQWN0aW9uKSkKICAgICR0YXNrLldhaXQoKSB8IE91dC1OdWxsCn0KCmZ1bmN0aW9uIEdldC1PY3JFbmdpbmUgewogICAgQWRkLVR5cGUgLUFzc2VtYmx5TmFtZSBTeXN0ZW0uUnVu"
	+ "dGltZS5XaW5kb3dzUnVudGltZQogICAgJG51bGwgPSBbV2luZG93cy5TdG9yYWdlLlN0b3JhZ2VGaWxlLCBXaW5kb3dzLlN0b3JhZ2UsIENvbnRlbnRUeXBlID0gV2luZG93c1J1bnRpbWVdCiAgICAkbnVsbCA9IFtXaW5kb3dzLkRhdGEu"
	+ "UGRmLlBkZkRvY3VtZW50LCBXaW5kb3dzLkRhdGEuUGRmLCBDb250ZW50VHlwZSA9IFdpbmRvd3NSdW50aW1lXQogICAgJG51bGwgPSBbV2luZG93cy5EYXRhLlBkZi5QZGZQYWdlUmVuZGVyT3B0aW9ucywgV2luZG93cy5EYXRhLlBkZiwg"
	+ "Q29udGVudFR5cGUgPSBXaW5kb3dzUnVudGltZV0KICAgICRudWxsID0gW1dpbmRvd3MuU3RvcmFnZS5TdHJlYW1zLkluTWVtb3J5UmFuZG9tQWNjZXNzU3RyZWFtLCBXaW5kb3dzLlN0b3JhZ2UuU3RyZWFtcywgQ29udGVudFR5cGUgPSBX"
	+ "aW5kb3dzUnVudGltZV0KICAgICRudWxsID0gW1dpbmRvd3MuR3JhcGhpY3MuSW1hZ2luZy5CaXRtYXBEZWNvZGVyLCBXaW5kb3dzLkdyYXBoaWNzLkltYWdpbmcsIENvbnRlbnRUeXBlID0gV2luZG93c1J1bnRpbWVdCiAgICAkbnVsbCA9"
	+ "IFtXaW5kb3dzLkdyYXBoaWNzLkltYWdpbmcuU29mdHdhcmVCaXRtYXAsIFdpbmRvd3MuR3JhcGhpY3MuSW1hZ2luZywgQ29udGVudFR5cGUgPSBXaW5kb3dzUnVudGltZV0KICAgICRudWxsID0gW1dpbmRvd3MuTWVkaWEuT2NyLk9jckVu"
	+ "Z2luZSwgV2luZG93cy5Gb3VuZGF0aW9uLCBDb250ZW50VHlwZSA9IFdpbmRvd3NSdW50aW1lXQogICAgJG51bGwgPSBbV2luZG93cy5NZWRpYS5PY3IuT2NyUmVzdWx0LCBXaW5kb3dzLkZvdW5kYXRpb24sIENvbnRlbnRUeXBlID0gV2lu"
	+ "ZG93c1J1bnRpbWVdCiAgICAkbnVsbCA9IFtXaW5kb3dzLkdsb2JhbGl6YXRpb24uTGFuZ3VhZ2UsIFdpbmRvd3MuR2xvYmFsaXphdGlvbiwgQ29udGVudFR5cGUgPSBXaW5kb3dzUnVudGltZV0KICAgIGZvcmVhY2ggKCR0YWcgaW4gQCgi"
	+ "cnUtUlUiLCAicnUiKSkgewogICAgICAgIHRyeSB7CiAgICAgICAgICAgICRlbmdpbmUgPSBbV2luZG93cy5NZWRpYS5PY3IuT2NyRW5naW5lXTo6VHJ5Q3JlYXRlRnJvbUxhbmd1YWdlKFtXaW5kb3dzLkdsb2JhbGl6YXRpb24uTGFuZ3Vh"
	+ "Z2VdOjpuZXcoJHRhZykpCiAgICAgICAgICAgIGlmICgkZW5naW5lKSB7IHJldHVybiAkZW5naW5lIH0KICAgICAgICB9IGNhdGNoIHt9CiAgICB9CiAgICAkZW5naW5lID0gW1dpbmRvd3MuTWVkaWEuT2NyLk9jckVuZ2luZV06OlRyeUNy"
	+ "ZWF0ZUZyb21Vc2VyUHJvZmlsZUxhbmd1YWdlcygpCiAgICBpZiAoJGVuZ2luZSkgeyByZXR1cm4gJGVuZ2luZSB9CiAgICB0aHJvdyAi0J3QsCDRgdC10YDQstC10YDQtSDQvdC10YIg0YDRg9GB0YHQutC+0LPQviBPQ1IgV2luZG93cy4g"
	+ "0JIg0L/QsNGA0LDQvNC10YLRgNCw0YUg0Y/Qt9GL0LrQsCDQtNC+0LHQsNCy0YzRgtC1INGA0YPRgdGB0LrQuNC5INGP0LfRi9C60L7QstC+0Lkg0L/QsNC60LXRgiDRgSDRgNCw0YHQv9C+0LfQvdCw0LLQsNC90LjQtdC8INGC0LXQutGB"
	+ "0YLQsC4iCn0KCmZ1bmN0aW9uIEdldC1PY3JUZXh0KFtzdHJpbmddJFBhdGgpIHsKICAgICRlbmdpbmUgPSBHZXQtT2NyRW5naW5lCiAgICAkZmlsZSA9IEF3YWl0LVdpblJUIChbV2luZG93cy5TdG9yYWdlLlN0b3JhZ2VGaWxlXTo6R2V0"
	+ "RmlsZUZyb21QYXRoQXN5bmMoJFBhdGgpKSAoW1dpbmRvd3MuU3RvcmFnZS5TdG9yYWdlRmlsZV0pCiAgICAkcGRmID0gQXdhaXQtV2luUlQgKFtXaW5kb3dzLkRhdGEuUGRmLlBkZkRvY3VtZW50XTo6TG9hZEZyb21GaWxlQXN5bmMoJGZp"
	+ "bGUpKSAoW1dpbmRvd3MuRGF0YS5QZGYuUGRmRG9jdW1lbnRdKQogICAgJHBhZ2VzID0gTmV3LU9iamVjdCBTeXN0ZW0uQ29sbGVjdGlvbnMuR2VuZXJpYy5MaXN0W3N0cmluZ10KICAgICRsaW1pdCA9IFtNYXRoXTo6TWluKFtpbnRdJHBk"
	+ "Zi5QYWdlQ291bnQsIDIpCiAgICBmb3IgKCRpID0gMDsgJGkgLWx0ICRsaW1pdDsgJGkrKykgewogICAgICAgICRwYWdlID0gJHBkZi5HZXRQYWdlKFt1aW50MzJdJGkpCiAgICAgICAgJHN0cmVhbSA9ICRudWxsCiAgICAgICAgJGJpdG1h"
	+ "cCA9ICRudWxsCiAgICAgICAgdHJ5IHsKICAgICAgICAgICAgJHN0cmVhbSA9IE5ldy1PYmplY3QgV2luZG93cy5TdG9yYWdlLlN0cmVhbXMuSW5NZW1vcnlSYW5kb21BY2Nlc3NTdHJlYW0KICAgICAgICAgICAgJG9wdGlvbnMgPSBOZXct"
	+ "T2JqZWN0IFdpbmRvd3MuRGF0YS5QZGYuUGRmUGFnZVJlbmRlck9wdGlvbnMKICAgICAgICAgICAgJHdpZHRoID0gMTcwMAogICAgICAgICAgICB0cnkgewogICAgICAgICAgICAgICAgaWYgKCRwYWdlLlNpemUuV2lkdGggLWd0IDEwMCkg"
	+ "eyAkd2lkdGggPSBbaW50XSgkcGFnZS5TaXplLldpZHRoICogMi41KSB9CiAgICAgICAgICAgIH0gY2F0Y2gge30KICAgICAgICAgICAgJG9wdGlvbnMuRGVzdGluYXRpb25XaWR0aCA9IFt1aW50MzJdJHdpZHRoCiAgICAgICAgICAgIEF3"
	+ "YWl0LVdpblJUQWN0aW9uICgkcGFnZS5SZW5kZXJUb1N0cmVhbUFzeW5jKCRzdHJlYW0sICRvcHRpb25zKSkKICAgICAgICAgICAgJHN0cmVhbS5TZWVrKDApIHwgT3V0LU51bGwKICAgICAgICAgICAgJGRlY29kZXIgPSBBd2FpdC1XaW5S"
	+ "VCAoW1dpbmRvd3MuR3JhcGhpY3MuSW1hZ2luZy5CaXRtYXBEZWNvZGVyXTo6Q3JlYXRlQXN5bmMoJHN0cmVhbSkpIChbV2luZG93cy5HcmFwaGljcy5JbWFnaW5nLkJpdG1hcERlY29kZXJdKQogICAgICAgICAgICAkYml0bWFwID0gQXdh"
	+ "aXQtV2luUlQgKCRkZWNvZGVyLkdldFNvZnR3YXJlQml0bWFwQXN5bmMoKSkgKFtXaW5kb3dzLkdyYXBoaWNzLkltYWdpbmcuU29mdHdhcmVCaXRtYXBdKQogICAgICAgICAgICBpZiAoJGJpdG1hcC5CaXRtYXBQaXhlbEZvcm1hdCAtbmUg"
	+ "W1dpbmRvd3MuR3JhcGhpY3MuSW1hZ2luZy5CaXRtYXBQaXhlbEZvcm1hdF06OkJncmE4KSB7CiAgICAgICAgICAgICAgICAkYml0bWFwID0gW1dpbmRvd3MuR3JhcGhpY3MuSW1hZ2luZy5Tb2Z0d2FyZUJpdG1hcF06OkNvbnZlcnQoCiAg"
	+ "ICAgICAgICAgICAgICAgICAgJGJpdG1hcCwKICAgICAgICAgICAgICAgICAgICBbV2luZG93cy5HcmFwaGljcy5JbWFnaW5nLkJpdG1hcFBpeGVsRm9ybWF0XTo6QmdyYTgsCiAgICAgICAgICAgICAgICAgICAgW1dpbmRvd3MuR3JhcGhp"
	+ "Y3MuSW1hZ2luZy5CaXRtYXBBbHBoYU1vZGVdOjpQcmVtdWx0aXBsaWVkKQogICAgICAgICAgICB9CiAgICAgICAgICAgICRyZWNvZ25pemVkID0gQXdhaXQtV2luUlQgKCRlbmdpbmUuUmVjb2duaXplQXN5bmMoJGJpdG1hcCkpIChbV2lu"
	+ "ZG93cy5NZWRpYS5PY3IuT2NyUmVzdWx0XSkKICAgICAgICAgICAgJGxpbmVzID0gTmV3LU9iamVjdCBTeXN0ZW0uQ29sbGVjdGlvbnMuR2VuZXJpYy5MaXN0W3N0cmluZ10KICAgICAgICAgICAgZm9yZWFjaCAoJGxpbmUgaW4gJHJlY29n"
	+ "bml6ZWQuTGluZXMpIHsgJGxpbmVzLkFkZCgkbGluZS5UZXh0KSB9CiAgICAgICAgICAgIGlmICgkbGluZXMuQ291bnQgLWd0IDApIHsgJHBhZ2VzLkFkZCgoJGxpbmVzIC1qb2luICJgbiIpKSB9CiAgICAgICAgICAgIGVsc2VpZiAoJHJl"
	+ "Y29nbml6ZWQuVGV4dCkgeyAkcGFnZXMuQWRkKCRyZWNvZ25pemVkLlRleHQpIH0KICAgICAgICB9IGZpbmFsbHkgewogICAgICAgICAgICBpZiAoJGJpdG1hcCkgeyAkYml0bWFwLkRpc3Bvc2UoKSB9CiAgICAgICAgICAgIGlmICgkc3Ry"
	+ "ZWFtKSB7ICRzdHJlYW0uRGlzcG9zZSgpIH0KICAgICAgICAgICAgJHBhZ2UuRGlzcG9zZSgpCiAgICAgICAgfQogICAgfQogICAgcmV0dXJuICgkcGFnZXMgLWpvaW4gImBuIikuVHJpbSgpCn0KCmZ1bmN0aW9uIEluZmxhdGUtWmxpYihb"
	+ "Ynl0ZVtdXSRSYXcpIHsKICAgIGlmICgkbnVsbCAtZXEgJFJhdyAtb3IgJFJhdy5MZW5ndGggLWx0IDMpIHsgcmV0dXJuICRudWxsIH0KICAgICRza2lwID0gMgogICAgaWYgKCRSYXdbMF0gLWVxIDEyMCAtYW5kICgoJFJhd1sxXSAtYmFu"
	+ "ZCAzMikgLW5lIDApKSB7ICRza2lwID0gNiB9CiAgICBpZiAoJFJhdy5MZW5ndGggLWxlICRza2lwKSB7IHJldHVybiAkbnVsbCB9CiAgICAkbGVuID0gJFJhdy5MZW5ndGggLSAkc2tpcAogICAgJHBheWxvYWQgPSBOZXctT2JqZWN0IGJ5"
	+ "dGVbXSAkbGVuCiAgICBbU3lzdGVtLkFycmF5XTo6Q29weSgkUmF3LCAkc2tpcCwgJHBheWxvYWQsIDAsICRsZW4pCiAgICAkaW5wdXQgPSBOZXctT2JqZWN0IFN5c3RlbS5JTy5NZW1vcnlTdHJlYW0oLCRwYXlsb2FkKQogICAgJGRlZmxh"
	+ "dGUgPSBOZXctT2JqZWN0IFN5c3RlbS5JTy5Db21wcmVzc2lvbi5EZWZsYXRlU3RyZWFtKCRpbnB1dCwgW1N5c3RlbS5JTy5Db21wcmVzc2lvbi5Db21wcmVzc2lvbk1vZGVdOjpEZWNvbXByZXNzKQogICAgJG91dHB1dCA9IE5ldy1PYmpl"
	+ "Y3QgU3lzdGVtLklPLk1lbW9yeVN0cmVhbQogICAgdHJ5IHsKICAgICAgICAkZGVmbGF0ZS5Db3B5VG8oJG91dHB1dCkKICAgIH0gY2F0Y2ggewogICAgICAgIHJldHVybiAkbnVsbAogICAgfSBmaW5hbGx5IHsKICAgICAgICAkZGVmbGF0"
	+ "ZS5EaXNwb3NlKCkKICAgICAgICAkaW5wdXQuRGlzcG9zZSgpCiAgICB9CiAgICByZXR1cm4gJG91dHB1dC5Ub0FycmF5KCkKfQoKZnVuY3Rpb24gR2V0LVN0cmVhbUJ5dGVzKFtzdHJpbmddJEJvZHkpIHsKICAgICRtYXRjaCA9IFtyZWdl"
	+ "eF06Ok1hdGNoKCRCb2R5LCAic3RyZWFtXHI/XG4oW1xzXFNdKj8pXHI/XG5lbmRzdHJlYW0iKQogICAgaWYgKC1ub3QgJG1hdGNoLlN1Y2Nlc3MpIHsgcmV0dXJuICRudWxsIH0KICAgICRsYXRpbiA9IFtTeXN0ZW0uVGV4dC5FbmNvZGlu"
	+ "Z106OkdldEVuY29kaW5nKDI4NTkxKQogICAgJHJhdyA9ICRsYXRpbi5HZXRCeXRlcygkbWF0Y2guR3JvdXBzWzFdLlZhbHVlKQogICAgJGhlYWQgPSAkQm9keS5TdWJzdHJpbmcoMCwgW01hdGhdOjpNaW4oJG1hdGNoLkluZGV4LCAkQm9k"
	+ "eS5MZW5ndGgpKQogICAgaWYgKCRoZWFkIC1tYXRjaCAiRmxhdGVEZWNvZGUiKSB7CiAgICAgICAgJGluZmxhdGVkID0gSW5mbGF0ZS1abGliICRyYXcKICAgICAgICBpZiAoJG51bGwgLW5lICRpbmZsYXRlZCkgeyByZXR1cm4gJGluZmxh"
	+ "dGVkIH0KICAgIH0KICAgIHJldHVybiAkcmF3Cn0KCmZ1bmN0aW9uIFBhcnNlLUNNYXAoW3N0cmluZ10kQ01hcFRleHQpIHsKICAgICRtYXAgPSBAe30KICAgICRibG9ja3MgPSAkQ01hcFRleHQgLXNwbGl0ICJiZWdpbmJmY2hhciIKICAg"
	+ "IGZvciAoJGkgPSAxOyAkaSAtbHQgJGJsb2Nrcy5Db3VudDsgJGkrKykgewogICAgICAgICRwYXJ0ID0gKCRibG9ja3NbJGldIC1zcGxpdCAiZW5kYmZjaGFyIilbMF0KICAgICAgICBmb3JlYWNoICgkcGFpciBpbiBbcmVnZXhdOjpNYXRj"
	+ "aGVzKCRwYXJ0LCAiPChbMC05QS1GYS1mXSspPlxzKjwoWzAtOUEtRmEtZl0rKT4iKSkgewogICAgICAgICAgICAkc3JjID0gW0NvbnZlcnRdOjpUb0ludDMyKCRwYWlyLkdyb3Vwc1sxXS5WYWx1ZSwgMTYpCiAgICAgICAgICAgICRkc3Qg"
	+ "PSAkcGFpci5Hcm91cHNbMl0uVmFsdWUKICAgICAgICAgICAgJGNoYXJzID0gIiIKICAgICAgICAgICAgZm9yICgkayA9IDA7ICRrICsgNCAtbGUgJGRzdC5MZW5ndGg7ICRrICs9IDQpIHsKICAgICAgICAgICAgICAgICRjaGFycyArPSBb"
	+ "Y2hhcl1bQ29udmVydF06OlRvSW50MzIoJGRzdC5TdWJzdHJpbmcoJGssIDQpLCAxNikKICAgICAgICAgICAgfQogICAgICAgICAgICAkbWFwWyRzcmNdID0gJGNoYXJzCiAgICAgICAgfQogICAgfQogICAgcmV0dXJuICRtYXAKfQoKZnVu"
	+ "Y3Rpb24gRGVjb2RlLVBkZlN0cmluZyhbc3RyaW5nXSRWYWx1ZSwgJE1hcCkgewogICAgJGJ5dGVzID0gTmV3LU9iamVjdCBTeXN0ZW0uQ29sbGVjdGlvbnMuR2VuZXJpYy5MaXN0W2ludF0KICAgIGZvciAoJGkgPSAwOyAkaSAtbHQgJFZh"
	+ "bHVlLkxlbmd0aDsgJGkrKykgewogICAgICAgICRjaCA9ICRWYWx1ZVskaV0KICAgICAgICBpZiAoJGNoIC1lcSAiXCIpIHsKICAgICAgICAgICAgJG5leHQgPSBpZiAoJGkgKyAxIC1sdCAkVmFsdWUuTGVuZ3RoKSB7ICRWYWx1ZVskaSAr"
	+ "IDFdIH0gZWxzZSB7ICIiIH0KICAgICAgICAgICAgaWYgKCRuZXh0IC1tYXRjaCAiWzAtN10iKSB7CiAgICAgICAgICAgICAgICAkb2N0ID0gIiIKICAgICAgICAgICAgICAgICRqID0gMQogICAgICAgICAgICAgICAgd2hpbGUgKCRqIC1s"
	+ "ZSAzIC1hbmQgKCRpICsgJGopIC1sdCAkVmFsdWUuTGVuZ3RoIC1hbmQgJFZhbHVlWyRpICsgJGpdIC1tYXRjaCAiWzAtN10iKSB7CiAgICAgICAgICAgICAgICAgICAgJG9jdCArPSAkVmFsdWVbJGkgKyAkal0KICAgICAgICAgICAgICAg"
	+ "ICAgICAkaisrCiAgICAgICAgICAgICAgICB9CiAgICAgICAgICAgICAgICAkYnl0ZXMuQWRkKFtDb252ZXJ0XTo6VG9JbnQzMigkb2N0LCA4KSkKICAgICAgICAgICAgICAgICRpICs9ICRqIC0gMQogICAgICAgICAgICB9IGVsc2Ugewog"
	+ "ICAgICAgICAgICAgICAgJGJ5dGVzLkFkZChbaW50XVtjaGFyXSRuZXh0KQogICAgICAgICAgICAgICAgJGkrKwogICAgICAgICAgICB9CiAgICAgICAgfSBlbHNlIHsKICAgICAgICAgICAgJGJ5dGVzLkFkZCgoW2ludF1bY2hhcl0kY2gp"
	+ "IC1iYW5kIDI1NSkKICAgICAgICB9CiAgICB9CiAgICAkdHdvID0gJGZhbHNlCiAgICBmb3JlYWNoICgka2V5IGluICRNYXAuS2V5cykgeyBpZiAoW2ludF0ka2V5IC1ndCAyNTUpIHsgJHR3byA9ICR0cnVlOyBicmVhayB9IH0KICAgICR0"
	+ "ZXh0ID0gIiIKICAgIGlmICgkdHdvKSB7CiAgICAgICAgZm9yICgkaSA9IDA7ICRpICsgMSAtbHQgJGJ5dGVzLkNvdW50OyAkaSArPSAyKSB7CiAgICAgICAgICAgICRjb2RlID0gKCRieXRlc1skaV0gLXNobCA4KSAtYm9yICRieXRlc1sk"
	+ "aSArIDFdCiAgICAgICAgICAgIGlmICgkTWFwLkNvbnRhaW5zS2V5KCRjb2RlKSkgeyAkdGV4dCArPSAkTWFwWyRjb2RlXSB9CiAgICAgICAgfQogICAgfSBlbHNlIHsKICAgICAgICBmb3JlYWNoICgkYiBpbiAkYnl0ZXMpIHsKICAgICAg"
	+ "ICAgICAgaWYgKCRNYXAuQ29udGFpbnNLZXkoJGIpKSB7ICR0ZXh0ICs9ICRNYXBbJGJdIH0KICAgICAgICB9CiAgICB9CiAgICByZXR1cm4gJHRleHQKfQoKZnVuY3Rpb24gSW52b2tlLUV4dHJhY3Qgewp0cnkgewogICAgJGZpbGVCeXRl"
	+ "cyA9IFtTeXN0ZW0uSU8uRmlsZV06OlJlYWRBbGxCeXRlcygkUGRmUGF0aCkKICAgICRsYXRpbiA9IFtTeXN0ZW0uVGV4dC5FbmNvZGluZ106OkdldEVuY29kaW5nKDI4NTkxKQogICAgJHNvdXJjZSA9ICRsYXRpbi5HZXRTdHJpbmcoJGZp"
	+ "bGVCeXRlcykKICAgICRvYmplY3RzID0gQHt9CiAgICBmb3JlYWNoICgkb2JqIGluIFtyZWdleF06Ok1hdGNoZXMoJHNvdXJjZSwgIihcZCspXHMrMFxzK29iaihbXHNcU10qPyllbmRvYmoiKSkgewogICAgICAgICRvYmplY3RzW1tpbnRd"
	+ "JG9iai5Hcm91cHNbMV0uVmFsdWVdID0gJG9iai5Hcm91cHNbMl0uVmFsdWUKICAgIH0KCiAgICAkZm9udE1hcHMgPSBAe30KICAgIGZvcmVhY2ggKCRpZCBpbiBAKCRvYmplY3RzLktleXMpKSB7CiAgICAgICAgJGJvZHkgPSAkb2JqZWN0"
	+ "c1skaWRdCiAgICAgICAgJHRvID0gW3JlZ2V4XTo6TWF0Y2goJGJvZHksICIvVG9Vbmljb2RlXHMrKFxkKylccyswXHMrUiIpCiAgICAgICAgaWYgKC1ub3QgJHRvLlN1Y2Nlc3MpIHsgY29udGludWUgfQogICAgICAgICR0YXJnZXRJZCA9"
	+ "IFtpbnRdJHRvLkdyb3Vwc1sxXS5WYWx1ZQogICAgICAgIGlmICgtbm90ICRvYmplY3RzLkNvbnRhaW5zS2V5KCR0YXJnZXRJZCkpIHsgY29udGludWUgfQogICAgICAgICRzdHJlYW0gPSBHZXQtU3RyZWFtQnl0ZXMgJG9iamVjdHNbJHRh"
	+ "cmdldElkXQogICAgICAgIGlmICgkbnVsbCAtZXEgJHN0cmVhbSkgeyBjb250aW51ZSB9CiAgICAgICAgJGZvbnRNYXBzWyRpZF0gPSBQYXJzZS1DTWFwICgkbGF0aW4uR2V0U3RyaW5nKCRzdHJlYW0pKQogICAgfQoKICAgICRwYWdlcyA9"
	+ "IE5ldy1PYmplY3QgU3lzdGVtLkNvbGxlY3Rpb25zLkdlbmVyaWMuTGlzdFtzdHJpbmddCiAgICBmb3JlYWNoICgkaWQgaW4gQCgkb2JqZWN0cy5LZXlzKSkgewogICAgICAgICRib2R5ID0gJG9iamVjdHNbJGlkXQogICAgICAgIGlmICgk"
	+ "Ym9keSAtbm90bWF0Y2ggIi9Db250ZW50cyIgLW9yICRib2R5IC1ub3RtYXRjaCAiL0ZvbnQiKSB7IGNvbnRpbnVlIH0KICAgICAgICAkZm9udEJsb2NrID0gW3JlZ2V4XTo6TWF0Y2goJGJvZHksICIvRm9udFxzKjw8KFtcc1xTXSo/KT4+"
	+ "IikKICAgICAgICBpZiAoLW5vdCAkZm9udEJsb2NrLlN1Y2Nlc3MpIHsgY29udGludWUgfQogICAgICAgICRmb250cyA9IEB7fQogICAgICAgIGZvcmVhY2ggKCRmb250IGluIFtyZWdleF06Ok1hdGNoZXMoJGZvbnRCbG9jay5Hcm91cHNb"
	+ "MV0uVmFsdWUsICIvKEZcZCspXHMrKFxkKylccyswXHMrUiIpKSB7CiAgICAgICAgICAgICRmb250c1skZm9udC5Hcm91cHNbMV0uVmFsdWVdID0gW2ludF0kZm9udC5Hcm91cHNbMl0uVmFsdWUKICAgICAgICB9CiAgICAgICAgJGNvbnRl"
	+ "bnRzID0gW3JlZ2V4XTo6TWF0Y2goJGJvZHksICIvQ29udGVudHNccysoXGQrKVxzKzBccytSIikKICAgICAgICBpZiAoLW5vdCAkY29udGVudHMuU3VjY2VzcykgeyBjb250aW51ZSB9CiAgICAgICAgJGNvbnRlbnRJZCA9IFtpbnRdJGNv"
	+ "bnRlbnRzLkdyb3Vwc1sxXS5WYWx1ZQogICAgICAgIGlmICgtbm90ICRvYmplY3RzLkNvbnRhaW5zS2V5KCRjb250ZW50SWQpKSB7IGNvbnRpbnVlIH0KICAgICAgICAkc3RyZWFtID0gR2V0LVN0cmVhbUJ5dGVzICRvYmplY3RzWyRjb250"
	+ "ZW50SWRdCiAgICAgICAgaWYgKCRudWxsIC1lcSAkc3RyZWFtKSB7IGNvbnRpbnVlIH0KICAgICAgICAkd29yayA9ICRsYXRpbi5HZXRTdHJpbmcoJHN0cmVhbSkKICAgICAgICAkdG9rZW4gPSBbcmVnZXhdIi8oRlxkKylccytbMC05Ll0r"
	+ "XHMrVGZ8KC0/XGQrXC5cZCt8LT9cZCspXHMrKC0/XGQrXC5cZCt8LT9cZCspXHMrVGR8XFsoKD86XFxbXHNcU118W15cXVxcXSkqKVxdXHMqVEp8XGJCVFxiIgogICAgICAgICR4ID0gMC4wCiAgICAgICAgJHkgPSAwLjAKICAgICAgICAk"
	+ "Zm9udE5hbWUgPSAkbnVsbAogICAgICAgICRpdGVtcyA9IEAoKQogICAgICAgIGZvcmVhY2ggKCR0b2sgaW4gW3JlZ2V4XTo6TWF0Y2hlcygkd29yaywgJHRva2VuKSkgewogICAgICAgICAgICAkcGllY2UgPSAkdG9rLlZhbHVlCiAgICAg"
	+ "ICAgICAgIGlmICgkcGllY2UgLWVxICJCVCIpIHsgJHggPSAwOyAkeSA9IDA7IGNvbnRpbnVlIH0KICAgICAgICAgICAgaWYgKCR0b2suR3JvdXBzWzFdLlN1Y2Nlc3MpIHsgJGZvbnROYW1lID0gJHRvay5Hcm91cHNbMV0uVmFsdWU7IGNv"
	+ "bnRpbnVlIH0KICAgICAgICAgICAgaWYgKCRwaWVjZSAtbWF0Y2ggIlRkJCIpIHsKICAgICAgICAgICAgICAgICR4ICs9IFtkb3VibGVdJHRvay5Hcm91cHNbMl0uVmFsdWUKICAgICAgICAgICAgICAgICR5ICs9IFtkb3VibGVdJHRvay5H"
	+ "cm91cHNbM10uVmFsdWUKICAgICAgICAgICAgICAgIGNvbnRpbnVlCiAgICAgICAgICAgIH0KICAgICAgICAgICAgaWYgKC1ub3QgJHRvay5Hcm91cHNbNF0uU3VjY2VzcyAtb3IgLW5vdCAkZm9udE5hbWUpIHsgY29udGludWUgfQogICAg"
	+ "ICAgICAgICBpZiAoLW5vdCAkZm9udHMuQ29udGFpbnNLZXkoJGZvbnROYW1lKSkgeyBjb250aW51ZSB9CiAgICAgICAgICAgICRmb250SWQgPSAkZm9udHNbJGZvbnROYW1lXQogICAgICAgICAgICBpZiAoLW5vdCAkZm9udE1hcHMuQ29u"
	+ "dGFpbnNLZXkoJGZvbnRJZCkpIHsgY29udGludWUgfQogICAgICAgICAgICAkbWFwID0gJGZvbnRNYXBzWyRmb250SWRdCiAgICAgICAgICAgICRkZWNvZGVkID0gIiIKICAgICAgICAgICAgZm9yZWFjaCAoJHN0ciBpbiBbcmVnZXhdOjpN"
	+ "YXRjaGVzKCR0b2suR3JvdXBzWzRdLlZhbHVlLCAiXCgoKD86XFwufFteXFwpXSkqKVwpIikpIHsKICAgICAgICAgICAgICAgICRkZWNvZGVkICs9IERlY29kZS1QZGZTdHJpbmcgJHN0ci5Hcm91cHNbMV0uVmFsdWUgJG1hcAogICAgICAg"
	+ "ICAgICB9CiAgICAgICAgICAgIGlmICgkZGVjb2RlZCkgeyAkaXRlbXMgKz0gW3BzY3VzdG9tb2JqZWN0XUB7IFggPSAkeDsgWSA9IFttYXRoXTo6Um91bmQoJHkpOyBUZXh0ID0gJGRlY29kZWQgfSB9CiAgICAgICAgfQogICAgICAgICRp"
	+ "dGVtcyA9ICRpdGVtcyB8IFNvcnQtT2JqZWN0IEB7IEV4cHJlc3Npb24gPSAiWSI7IERlc2NlbmRpbmcgPSAkdHJ1ZSB9LCBAeyBFeHByZXNzaW9uID0gIlgiOyBEZXNjZW5kaW5nID0gJGZhbHNlIH0KICAgICAgICAkbGluZXMgPSBOZXct"
	+ "T2JqZWN0IFN5c3RlbS5Db2xsZWN0aW9ucy5HZW5lcmljLkxpc3Rbc3RyaW5nXQogICAgICAgICRsaW5lWSA9ICRudWxsCiAgICAgICAgJGJ1Y2tldCA9IEAoKQogICAgICAgIGZvcmVhY2ggKCRpdGVtIGluICRpdGVtcykgewogICAgICAg"
	+ "ICAgICBpZiAoJG51bGwgLWVxICRsaW5lWSAtb3IgW21hdGhdOjpBYnMoJGl0ZW0uWSAtICRsaW5lWSkgLWd0IDIpIHsKICAgICAgICAgICAgICAgIGlmICgkYnVja2V0LkNvdW50KSB7CiAgICAgICAgICAgICAgICAgICAgJGxpbmVzLkFk"
	+ "ZCgoKCRidWNrZXQgfCBTb3J0LU9iamVjdCBYIHwgRm9yRWFjaC1PYmplY3QgeyAkXy5UZXh0IH0pIC1qb2luICIgIikpCiAgICAgICAgICAgICAgICB9CiAgICAgICAgICAgICAgICAkYnVja2V0ID0gQCgkaXRlbSkKICAgICAgICAgICAg"
	+ "ICAgICRsaW5lWSA9ICRpdGVtLlkKICAgICAgICAgICAgfSBlbHNlIHsKICAgICAgICAgICAgICAgICRidWNrZXQgKz0gJGl0ZW0KICAgICAgICAgICAgfQogICAgICAgIH0KICAgICAgICBpZiAoJGJ1Y2tldC5Db3VudCkgewogICAgICAg"
	+ "ICAgICAkbGluZXMuQWRkKCgoJGJ1Y2tldCB8IFNvcnQtT2JqZWN0IFggfCBGb3JFYWNoLU9iamVjdCB7ICRfLlRleHQgfSkgLWpvaW4gIiAiKSkKICAgICAgICB9CiAgICAgICAgaWYgKCRsaW5lcy5Db3VudCkgeyAkcGFnZXMuQWRkKCgk"
	+ "bGluZXMgLWpvaW4gImBuIikpIH0KICAgIH0KCiAgICAkdGV4dCA9ICgkcGFnZXMgLWpvaW4gImBuIikuVHJpbSgpCiAgICAkc2NyaXB0OkZyb21TY2FuID0gJGZhbHNlCiAgICBpZiAoJHRleHQuTGVuZ3RoIC1sdCA0MCkgewogICAgICAg"
	+ "ICR0ZXh0ID0gR2V0LU9jclRleHQgJFBkZlBhdGgKICAgICAgICAkc2NyaXB0OkZyb21TY2FuID0gJHRydWUKICAgIH0KICAgIGlmIChbc3RyaW5nXTo6SXNOdWxsT3JXaGl0ZVNwYWNlKCR0ZXh0KSAtb3IgJHRleHQuTGVuZ3RoIC1sdCA0"
	+ "MCkgewogICAgICAgIFdyaXRlLUVycm9ySnNvbiAi0KHQutCw0L0g0L3QtSDRgNCw0YHQv9C+0LfQvdCw0L0uINCf0YDQvtCy0LXRgNGM0YLQtSwg0YfRgtC+INC90LAg0YHQtdGA0LLQtdGA0LUg0YPRgdGC0LDQvdC+0LLQu9C10L0g0YDR"
	+ "g9GB0YHQutC40LkgT0NSIFdpbmRvd3MuIgogICAgICAgIHJldHVybgogICAgfQoKICAgICRyZXN1bHQgPSBDb252ZXJ0LUludm9pY2VUZXh0ICR0ZXh0ICRUaXRsZQogICAgaWYgKCRzY3JpcHQ6RnJvbVNjYW4gLWFuZCAtbm90ICRyZXN1"
	+ "bHQu0J7RiNC40LHQutCwKSB7CiAgICAgICAgJHdhcm5pbmdzID0gQCgkcmVzdWx0LtCf0YDQtdC00YPQv9GA0LXQttC00LXQvdC40Y8pCiAgICAgICAgJHdhcm5pbmdzICs9ICLQotC10LrRgdGCINC/0L7Qu9GD0YfQtdC9INGA0LDRgdC/"
	+ "0L7Qt9C90LDQstCw0L3QuNC10Lwg0YHQutCw0L3QsC4iCiAgICAgICAgJHJlc3VsdC7Qn9GA0LXQtNGD0L/RgNC10LbQtNC10L3QuNGPID0gJHdhcm5pbmdzCiAgICB9CiAgICAkanNvbiA9ICRyZXN1bHQgfCBDb252ZXJ0VG8tSnNvbiAt"
	+ "RGVwdGggNiAtQ29tcHJlc3MKICAgIFtTeXN0ZW0uSU8uRmlsZV06OldyaXRlQWxsVGV4dCgkT3V0UGF0aCwgJGpzb24sIFtTeXN0ZW0uVGV4dC5VVEY4RW5jb2RpbmddOjpuZXcoJGZhbHNlKSkKfSBjYXRjaCB7CiAgICBXcml0ZS1FcnJv"
	+ "ckpzb24gKCLQndC1INGD0LTQsNC70L7RgdGMINC/0YDQvtGH0LjRgtCw0YLRjCBQREY6ICIgKyAkXy5FeGNlcHRpb24uTWVzc2FnZSkKfQp9CgpmdW5jdGlvbiBDb252ZXJ0LUludm9pY2VUZXh0KFtzdHJpbmddJFRleHQsIFtzdHJpbmdd"
	+ "JFRpdGxlKSB7CiAgICAkbm9ybSA9ICRUZXh0IC1yZXBsYWNlIFtjaGFyXTB4MDBBMCwgIiAiCiAgICAkaXNVcGQgPSAkbm9ybSAtbWF0Y2ggIig/aSnRg9C90LjQstC10YDRgdCw0LvRjNC90YvQuVxzK9C/0LXRgNC10LTQsNGC0L7Rh9C9"
	+ "0YvQuVxzK9C00L7QutGD0LzQtdC90YIiIC1vciAkVGl0bGUgLW1hdGNoICIoP2kp0YPQv9C0fNGB0YfQtdGCLdGE0LDQutGC0YPRgNCwfNGB0Ydb0LXRkV3Rgi3RhNCw0LrRgtGD0YDQsCIKICAgICRpc0ludm9pY2UgPSAkbm9ybSAtbWF0"
	+ "Y2ggIig/aSnRgdGH0LXRgltcc19dKtC90LBbXHNfXSrQvtC/0LvQsNGC0YMiIC1vciAkVGl0bGUgLW1hdGNoICIoP2kp0YHRh9C10YJbXHNfXSrQvdCwW1xzX10q0L7Qv9C70LDRgtGDfNGB0Ydb0LXRkV3Rgltcc19dKtC90LBbXHNfXSrQ"
	+ "vtC/0LvQsNGC0YMiCiAgICAkaXNGYWN0dXJhID0gJG5vcm0gLW1hdGNoICIoP2kp0YHRh9C10YIt0YTQsNC60YLRg9GA0LAiIC1vciAkVGl0bGUgLW1hdGNoICIoP2kp0YHRh9C10YIt0YTQsNC60YLRg9GA0LAiCiAgICBpZiAoLW5vdCAk"
	+ "aXNVcGQgLWFuZCAtbm90ICRpc0ludm9pY2UgLWFuZCAtbm90ICRpc0ZhY3R1cmEpIHsKICAgICAgICByZXR1cm4gQHsg0J7RiNC40LHQutCwID0gItCt0YLQviDQvdC1INGB0YfQtdGCINC90LAg0L7Qv9C70LDRgtGDINC4INC90LUg0KPQ"
	+ "n9CULiIgfQogICAgfQogICAgJHdhcm5pbmdzID0gTmV3LU9iamVjdCBTeXN0ZW0uQ29sbGVjdGlvbnMuR2VuZXJpYy5MaXN0W3N0cmluZ10KICAgICRudW1iZXIgPSAiIgogICAgJGRhdGUgPSAiIgogICAgJHRpdGxlID0gW3JlZ2V4XTo6"
	+ "TWF0Y2goJG5vcm0sICIoP2kp0YHRh9C10YJccyvQvdCwXHMr0L7Qv9C70LDRgtGDXHMr4oSWXHMqKFswLTlBLVphLXrQkC3Qr9CwLdGP0IHRkVwtL10rKVxzK9C+0YJccysoXGR7MSwyfSlccysoW9CwLdGP0ZFdKylccysoXGR7NH0pIikK"
	+ "ICAgIGlmICgtbm90ICR0aXRsZS5TdWNjZXNzKSB7CiAgICAgICAgJHRpdGxlID0gW3JlZ2V4XTo6TWF0Y2goJG5vcm0sICIoP2kpKD860YHRh9C10YIt0YTQsNC60YLRg9GA0LB80YPQv9C0KVxzKuKEllxzKihbMC05QS1aYS160JAt0K/Q"
	+ "sC3Rj9CB0ZFcLS9dKylccyvQvtGCXHMrKFxkezEsMn0pWy5cc10oXGR7MSwyfXxb0LAt0Y/RkV0rKVsuXHNdKFxkezR9KSIpCiAgICB9CiAgICBpZiAoJHRpdGxlLlN1Y2Nlc3MpIHsKICAgICAgICAkbnVtYmVyID0gJHRpdGxlLkdyb3Vw"
	+ "c1sxXS5WYWx1ZQogICAgICAgICRkYXRlID0gQ29udmVydC1Ub0lzbyAkdGl0bGUuR3JvdXBzWzJdLlZhbHVlICR0aXRsZS5Hcm91cHNbM10uVmFsdWUgJHRpdGxlLkdyb3Vwc1s0XS5WYWx1ZQogICAgfQogICAgaWYgKC1ub3QgJG51bWJl"
	+ "cikgeyAkd2FybmluZ3MuQWRkKCLQndC+0LzQtdGAINC00L7QutGD0LzQtdC90YLQsCDQvdC1INGA0LDRgdC/0L7Qt9C90LDQvS4iKSB9CiAgICBpZiAoLW5vdCAkZGF0ZSkgeyAkd2FybmluZ3MuQWRkKCLQlNCw0YLQsCDQtNC+0LrRg9C8"
	+ "0LXQvdGC0LAg0L3QtSDRgNCw0YHQv9C+0LfQvdCw0L3QsC4iKSB9CgogICAgJHN1cHBsaWVyID0gR2V0LVBhcnR5ICRub3JtICIoP2kp0L/QvtGB0YLQsNCy0YnQuNC6fNC/0YDQvtC00LDQstC10YYiICIoP2kp0L/QvtC60YPQv9Cw0YLQ"
	+ "tdC70Yx80LfQsNC60LDQt9GH0LjQuiIKICAgICRidXllciA9IEdldC1QYXJ0eSAkbm9ybSAiKD9pKdC/0L7QutGD0L/QsNGC0LXQu9GMfNC30LDQutCw0LfRh9C40LoiICIoP2kp0L7RgdC90L7QstCw0L3QuNC1OnzihJZccyvRgtC+0LLQ"
	+ "sNGA0Yt80LjRgtC+0LPQvjoiCiAgICBpZiAoLW5vdCAkc3VwcGxpZXIu0JjQndCdKSB7ICRzdXBwbGllciA9IE1lcmdlLVBhcnR5ICRzdXBwbGllciAoR2V0LUlubktwcCAkbm9ybSAi0L/RgNC+0LTQsNCy0YbQsCIpIH0KICAgIGlmICgt"
	+ "bm90ICRidXllci7QmNCd0J0pIHsgJGJ1eWVyID0gTWVyZ2UtUGFydHkgJGJ1eWVyIChHZXQtSW5uS3BwICRub3JtICLQv9C+0LrRg9C/0LDRgtC10LvRjyIpIH0KICAgIGlmICgtbm90ICRidXllci7QmNCd0J0gLW9yIC1ub3QgJHN1cHBs"
	+ "aWVyLtCY0J3QnSkgewogICAgICAgICRwYWlycyA9IFtyZWdleF06Ok1hdGNoZXMoJG5vcm0sICIoXGR7MTB9fFxkezEyfSlccyovXHMqKFxkezl9KSIpCiAgICAgICAgZm9yZWFjaCAoJHBhaXIgaW4gJHBhaXJzKSB7CiAgICAgICAgICAg"
	+ "ICRpbm4gPSAkcGFpci5Hcm91cHNbMV0uVmFsdWUKICAgICAgICAgICAgJGtwcCA9ICRwYWlyLkdyb3Vwc1syXS5WYWx1ZQogICAgICAgICAgICBpZiAoLW5vdCAkc3VwcGxpZXIu0JjQndCdIC1hbmQgJGlubiAtZXEgIjc3MTc1NTI3ODQi"
	+ "KSB7CiAgICAgICAgICAgICAgICAkc3VwcGxpZXIgPSBNZXJnZS1QYXJ0eSAkc3VwcGxpZXIgQHsg0JjQndCdID0gJGlubjsg0JrQn9CfID0gJGtwcCB9CiAgICAgICAgICAgIH0KICAgICAgICB9CiAgICAgICAgZm9yZWFjaCAoJHBhaXIg"
	+ "aW4gJHBhaXJzKSB7CiAgICAgICAgICAgICRpbm4gPSAkcGFpci5Hcm91cHNbMV0uVmFsdWUKICAgICAgICAgICAgJGtwcCA9ICRwYWlyLkdyb3Vwc1syXS5WYWx1ZQogICAgICAgICAgICBpZiAoLW5vdCAkYnV5ZXIu0JjQndCdIC1hbmQg"
	+ "JGlubiAtbmUgJHN1cHBsaWVyLtCY0J3QnSkgewogICAgICAgICAgICAgICAgJGJ1eWVyID0gTWVyZ2UtUGFydHkgJGJ1eWVyIEB7INCY0J3QnSA9ICRpbm47INCa0J/QnyA9ICRrcHAgfQogICAgICAgICAgICAgICAgYnJlYWsKICAgICAg"
	+ "ICAgICAgfQogICAgICAgIH0KICAgIH0KICAgIGlmICgtbm90ICRidXllci7QmNCd0J0pIHsgJHdhcm5pbmdzLkFkZCgi0JjQndCdINC/0L7QutGD0L/QsNGC0LXQu9GPINC90LUg0L3QsNC50LTQtdC9LiIpIH0KCiAgICAkYmFzaXMgPSAi"
	+ "IgogICAgJGJhc2lzTWF0Y2ggPSBbcmVnZXhdOjpNYXRjaCgkbm9ybSwgIig/aSnQvtGB0L3QvtCy0LDQvdC40LU6XHMqKC4rKSIpCiAgICBpZiAoJGJhc2lzTWF0Y2guU3VjY2VzcykgeyAkYmFzaXMgPSAoJGJhc2lzTWF0Y2guR3JvdXBz"
	+ "WzFdLlZhbHVlIC1zcGxpdCAiYG4iKVswXS5UcmltKCkgfQogICAgaWYgKC1ub3QgJGJhc2lzKSB7ICR3YXJuaW5ncy5BZGQoItCe0YHQvdC+0LLQsNC90LjQtSAo0LTQvtCz0L7QstC+0YApINC90LUg0L3QsNC50LTQtdC90L4uIikgfQoK"
	+ "ICAgICRiYW5rID0gR2V0LUJhbmsgJG5vcm0KICAgICRsaW5lcyA9IEdldC1MaW5lcyAkbm9ybQogICAgaWYgKCRsaW5lcy5Db3VudCAtZXEgMCkgeyAkd2FybmluZ3MuQWRkKCLQodGC0YDQvtC60Lgg0YLQsNCx0LvQuNGH0L3QvtC5INGH"
	+ "0LDRgdGC0Lgg0L3QtSDRgNCw0LfQvtCx0YDQsNC90YsuIikgfQoKICAgICR0b3RhbCA9IDAuMAogICAgJHRvdGFsTWF0Y2ggPSBbcmVnZXhdOjpNYXRjaCgkbm9ybSwgIig/aSnQstGB0LXQs9C+XHMr0LpccyvQvtC/0LvQsNGC0LU6XHMq"
	+ "KFtcZFxzXSssXGR7Mn0pIikKICAgIGlmICgkdG90YWxNYXRjaC5TdWNjZXNzKSB7ICR0b3RhbCA9IENvbnZlcnQtTW9uZXkgJHRvdGFsTWF0Y2guR3JvdXBzWzFdLlZhbHVlIH0KICAgIGVsc2VpZiAoJGxpbmVzLkNvdW50KSB7IGZvcmVh"
	+ "Y2ggKCRsaW5lIGluICRsaW5lcykgeyAkdG90YWwgKz0gJGxpbmUu0KHRg9C80LzQsCB9IH0KCiAgICAkdmF0UmF0ZSA9IC0xCiAgICAkdmF0U3VtID0gMC4wCiAgICAkdmF0TWF0Y2ggPSBbcmVnZXhdOjpNYXRjaCgkbm9ybSwgIig/aSnQ"
	+ "vdC00YFccyooXGQrKVxzKiVbOlxzXSooW1xkXHNdKyxcZHsyfSkiKQogICAgaWYgKCR2YXRNYXRjaC5TdWNjZXNzKSB7CiAgICAgICAgJHZhdFJhdGUgPSBbaW50XSR2YXRNYXRjaC5Hcm91cHNbMV0uVmFsdWUKICAgICAgICAkdmF0U3Vt"
	+ "ID0gQ29udmVydC1Nb25leSAkdmF0TWF0Y2guR3JvdXBzWzJdLlZhbHVlCiAgICB9IGVsc2VpZiAoJG5vcm0gLW1hdGNoICIoP2kp0LHQtdC3XHMr0L3QtNGBfNCx0LXQt1xzK9C90LDQu9C+0LPQsCIpIHsKICAgICAgICAkdmF0UmF0ZSA9"
	+ "IDAKICAgIH0gZWxzZSB7CiAgICAgICAgJHdhcm5pbmdzLkFkZCgi0KHRgtCw0LLQutCwINCd0JTQoSDQvdC1INC90LDQudC00LXQvdCwLiIpCiAgICB9CiAgICBpZiAoJG5vcm0gLW1hdGNoICIoP2kp0L3QvtC80LXRgNGC0LXQu9C10YTQ"
	+ "vtC90LBccyo9IikgeyAkd2FybmluZ3MuQWRkKCLQkiDQutCw0YDRgtC+0YfQutC1INC/0L7QutGD0L/QsNGC0LXQu9GPINC/0YPRgdGC0L7QuSDRgtC10LvQtdGE0L7QvS4iKSB9CgogICAgJGtpbmQgPSAi0KHRh9C10YIiCiAgICBpZiAo"
	+ "JGlzVXBkKSB7ICRraW5kID0gItCj0J/QlCIgfQogICAgcmV0dXJuIEB7CiAgICAgICAg0JLQuNC0ID0gJGtpbmQKICAgICAgICDQndC+0LzQtdGAID0gJG51bWJlcgogICAgICAgINCU0LDRgtCwID0gJGRhdGUKICAgICAgICDQn9C+0YHR"
	+ "gtCw0LLRidC40LogPSAkc3VwcGxpZXIKICAgICAgICDQn9C+0LrRg9C/0LDRgtC10LvRjCA9ICRidXllcgogICAgICAgINCe0YHQvdC+0LLQsNC90LjQtSA9ICRiYXNpcwogICAgICAgINCR0LDQvdC6ID0gJGJhbmsKICAgICAgICDQodGC"
	+ "0YDQvtC60LggPSAkbGluZXMKICAgICAgICDQodGD0LzQvNCwID0gW21hdGhdOjpSb3VuZCgkdG90YWwsIDIpCiAgICAgICAg0KHRgtCw0LLQutCw0J3QlNChID0gJHZhdFJhdGUKICAgICAgICDQodGD0LzQvNCw0J3QlNChID0gW21hdGhd"
	+ "OjpSb3VuZCgkdmF0U3VtLCAyKQogICAgICAgINCh0YPQvNC80LDQktC60LvRjtGH0LDQtdGC0J3QlNChID0gJHRydWUKICAgICAgICDQn9GA0LXQtNGD0L/RgNC10LbQtNC10L3QuNGPID0gQCgkd2FybmluZ3MuVG9BcnJheSgpKQogICAg"
	+ "ICAgINCi0LXQutGB0YIgPSAkbm9ybQogICAgfQp9CgpmdW5jdGlvbiBDb252ZXJ0LVRvSXNvKFtzdHJpbmddJERheSwgW3N0cmluZ10kTW9udGhSYXcsIFtzdHJpbmddJFllYXIpIHsKICAgICRtb250aHMgPSBAewogICAgICAgICLRj9C9"
	+ "0LLQsNGA0Y8iID0gMTsgItGE0LXQstGA0LDQu9GPIiA9IDI7ICLQvNCw0YDRgtCwIiA9IDM7ICLQsNC/0YDQtdC70Y8iID0gNDsgItC80LDRjyIgPSA1OyAi0LjRjtC90Y8iID0gNgogICAgICAgICLQuNGO0LvRjyIgPSA3OyAi0LDQstCz"
	+ "0YPRgdGC0LAiID0gODsgItGB0LXQvdGC0Y/QsdGA0Y8iID0gOTsgItC+0LrRgtGP0LHRgNGPIiA9IDEwOyAi0L3QvtGP0LHRgNGPIiA9IDExOyAi0LTQtdC60LDQsdGA0Y8iID0gMTIKICAgIH0KICAgICRtb250aCA9IDAKICAgIGlmICgk"
	+ "TW9udGhSYXcgLW1hdGNoICJeXGQrJCIpIHsgJG1vbnRoID0gW2ludF0kTW9udGhSYXcgfSBlbHNlIHsgJG1vbnRoID0gW2ludF0kbW9udGhzWyRNb250aFJhdy5Ub0xvd2VyKCldIH0KICAgICRkID0gMDsgJHkgPSAwCiAgICBbdm9pZF1b"
	+ "aW50XTo6VHJ5UGFyc2UoJERheSwgW3JlZl0kZCkKICAgIFt2b2lkXVtpbnRdOjpUcnlQYXJzZSgkWWVhciwgW3JlZl0keSkKICAgIGlmICgkeSAtbHQgMjAwMCAtb3IgJG1vbnRoIC1sdCAxIC1vciAkbW9udGggLWd0IDEyIC1vciAkZCAt"
	+ "bHQgMSAtb3IgJGQgLWd0IDMxKSB7IHJldHVybiAiIiB9CiAgICByZXR1cm4gInswOjAwMDB9LXsxOjAwfS17MjowMH0iIC1mICR5LCAkbW9udGgsICRkCn0KCmZ1bmN0aW9uIENvbnZlcnQtTW9uZXkoW3N0cmluZ10kUmF3KSB7CiAgICAk"
	+ "Y2xlYW4gPSAoJFJhdyAtcmVwbGFjZSAiXHMiLCAiIikgLXJlcGxhY2UgIiwiLCAiLiIKICAgICRuID0gMC4wCiAgICBbdm9pZF1bZG91YmxlXTo6VHJ5UGFyc2UoJGNsZWFuLCBbU3lzdGVtLkdsb2JhbGl6YXRpb24uTnVtYmVyU3R5bGVz"
	+ "XTo6QW55LCBbU3lzdGVtLkdsb2JhbGl6YXRpb24uQ3VsdHVyZUluZm9dOjpJbnZhcmlhbnRDdWx0dXJlLCBbcmVmXSRuKQogICAgcmV0dXJuIFttYXRoXTo6Um91bmQoJG4sIDIpCn0KCmZ1bmN0aW9uIEdldC1Jbm5LcHAoW3N0cmluZ10k"
	+ "VGV4dCwgW3N0cmluZ10kUm9sZSkgewogICAgJGRpcmVjdCA9IFtyZWdleF06Ok1hdGNoKCRUZXh0LCAiKD9pKdCY0J3QnVxzKi9ccyrQmtCf0J9ccyskUm9sZVxzKls6XHNdKihcZHsxMH18XGR7MTJ9KVxzKi9ccyooXGR7OX0pIikKICAg"
	+ "IGlmICgkZGlyZWN0LlN1Y2Nlc3MpIHsKICAgICAgICByZXR1cm4gQHsg0JjQndCdID0gJGRpcmVjdC5Hcm91cHNbMV0uVmFsdWU7INCa0J/QnyA9ICRkaXJlY3QuR3JvdXBzWzJdLlZhbHVlIH0KICAgIH0KICAgICRsYWJlbCA9IFtyZWdl"
	+ "eF06Ok1hdGNoKCRUZXh0LCAiKD9pKdCY0J3QnVxzKi9ccyrQmtCf0J9ccyskUm9sZSIpCiAgICBpZiAoLW5vdCAkbGFiZWwuU3VjY2VzcykgeyByZXR1cm4gJG51bGwgfQogICAgJGxlbiA9IFtNYXRoXTo6TWluKDMwMCwgJFRleHQuTGVu"
	+ "Z3RoIC0gJGxhYmVsLkluZGV4KQogICAgJHdpbmRvdyA9ICRUZXh0LlN1YnN0cmluZygkbGFiZWwuSW5kZXgsICRsZW4pCiAgICAkcGFpciA9IFtyZWdleF06Ok1hdGNoKCR3aW5kb3csICIoXGR7MTB9fFxkezEyfSlccyovXHMqKFxkezl9"
	+ "KSIpCiAgICBpZiAoLW5vdCAkcGFpci5TdWNjZXNzKSB7IHJldHVybiAkbnVsbCB9CiAgICByZXR1cm4gQHsg0JjQndCdID0gJHBhaXIuR3JvdXBzWzFdLlZhbHVlOyDQmtCf0J8gPSAkcGFpci5Hcm91cHNbMl0uVmFsdWUgfQp9CgpmdW5j"
	+ "dGlvbiBNZXJnZS1QYXJ0eSgkUGFydHksICRGb3VuZCkgewogICAgaWYgKCRudWxsIC1lcSAkRm91bmQpIHsgcmV0dXJuICRQYXJ0eSB9CiAgICBpZiAoLW5vdCAkUGFydHku0JjQndCdIC1hbmQgJEZvdW5kLtCY0J3QnSkgeyAkUGFydHku"
	+ "0JjQndCdID0gW3N0cmluZ10kRm91bmQu0JjQndCdIH0KICAgIGlmICgtbm90ICRQYXJ0eS7QmtCf0J8gLWFuZCAkRm91bmQu0JrQn9CfKSB7ICRQYXJ0eS7QmtCf0J8gPSBbc3RyaW5nXSRGb3VuZC7QmtCf0J8gfQogICAgcmV0dXJuICRQ"
	+ "YXJ0eQp9CgpmdW5jdGlvbiBHZXQtUGFydHkoW3N0cmluZ10kVGV4dCwgW3N0cmluZ10kU3RhcnRQYXR0ZXJuLCBbc3RyaW5nXSRFbmRQYXR0ZXJuKSB7CiAgICAkc3RhcnQgPSBbcmVnZXhdOjpNYXRjaCgkVGV4dCwgJFN0YXJ0UGF0dGVy"
	+ "bikKICAgIGlmICgtbm90ICRzdGFydC5TdWNjZXNzKSB7IHJldHVybiBAeyDQndCw0LjQvNC10L3QvtCy0LDQvdC40LUgPSAiIjsg0JjQndCdID0gIiI7INCa0J/QnyA9ICIiOyDQkNC00YDQtdGBID0gIiIgfSB9CiAgICAkcmVzdCA9ICRU"
	+ "ZXh0LlN1YnN0cmluZygkc3RhcnQuSW5kZXgpCiAgICAkZW5kID0gW3JlZ2V4XTo6TWF0Y2goJHJlc3QuU3Vic3RyaW5nKDEpLCAkRW5kUGF0dGVybikKICAgICRibG9jayA9IGlmICgkZW5kLlN1Y2Nlc3MpIHsgJHJlc3QuU3Vic3RyaW5n"
	+ "KDAsICRlbmQuSW5kZXggKyAxKSB9IGVsc2UgeyAkcmVzdCB9CiAgICAkYmxvY2sgPSAoJGJsb2NrIC1yZXBsYWNlICJccysiLCAiICIpLlRyaW0oKQogICAgJGlubiA9IFtyZWdleF06Ok1hdGNoKCRibG9jaywgIig/aSnQmNCd0J1ccyoo"
	+ "XGR7MTAsMTJ9KSIpCiAgICAka3BwID0gW3JlZ2V4XTo6TWF0Y2goJGJsb2NrLCAiKD9pKdCa0J/Qn1xzKihcZHs5fSkiKQogICAgJG5hbWUgPSBbcmVnZXhdOjpNYXRjaCgkYmxvY2ssICIoP2kpKD860L/QvtGB0YLQsNCy0YnQuNC6fNC/"
	+ "0YDQvtC00LDQstC10YZ80L/QvtC60YPQv9Cw0YLQtdC70Yx80LfQsNC60LDQt9GH0LjQuilccyooPzpcKFteKV0rXCk6KT9ccyooLis/KSxccyrQmNCd0J0iKQogICAgJGFkZHJlc3MgPSAiIgogICAgaWYgKCRrcHAuU3VjY2Vzcykgewog"
	+ "ICAgICAgICRjaHVua3MgPSBbcmVnZXhdOjpTcGxpdCgkYmxvY2ssICIoP2kp0JrQn9CfXHMqXGR7OX0sP1xzKiIpCiAgICAgICAgaWYgKCRjaHVua3MuQ291bnQgLWd0IDEpIHsKICAgICAgICAgICAgJGFkZHJlc3MgPSAkY2h1bmtzWzFd"
	+ "IC1yZXBsYWNlICIoP2kpXCjQuNGB0L/QvtC70L3QuNGC0LXQu9GMXCk6fFwo0LfQsNC60LDQt9GH0LjQulwpOiIsICIgIgogICAgICAgICAgICAkYWRkcmVzcyA9ICgkYWRkcmVzcyAtcmVwbGFjZSAiKD9pKdC90L7QvNC10YDRgtC10LvQ"
	+ "tdGE0L7QvdCwXHMqPSIsICIiIC1yZXBsYWNlICJccysiLCAiICIpLlRyaW0oKS5UcmltKCIsIikKICAgICAgICB9CiAgICB9CiAgICByZXR1cm4gQHsKICAgICAgICDQndCw0LjQvNC10L3QvtCy0LDQvdC40LUgPSAkbmFtZS5Hcm91cHNb"
	+ "MV0uVmFsdWUuVHJpbSgpCiAgICAgICAg0JjQndCdID0gJGlubi5Hcm91cHNbMV0uVmFsdWUKICAgICAgICDQmtCf0J8gPSAka3BwLkdyb3Vwc1sxXS5WYWx1ZQogICAgICAgINCQ0LTRgNC10YEgPSAkYWRkcmVzcwogICAgfQp9CgpmdW5j"
	+ "dGlvbiBHZXQtQmFuayhbc3RyaW5nXSRUZXh0KSB7CiAgICAkaGVhZCA9ICRUZXh0CiAgICAkY3V0ID0gW3JlZ2V4XTo6TWF0Y2goJFRleHQsICIoP2kp0YHRh9C10YJccyvQvdCwXHMr0L7Qv9C70LDRgtGDfNGD0L3QuNCy0LXRgNGB0LDQ"
	+ "u9GM0L3Ri9C5XHMr0L/QtdGA0LXQtNCw0YLQvtGH0L3Ri9C5IikKICAgIGlmICgkY3V0LlN1Y2Nlc3MpIHsgJGhlYWQgPSAkVGV4dC5TdWJzdHJpbmcoMCwgJGN1dC5JbmRleCkgfQogICAgJGJpayA9IFtyZWdleF06Ok1hdGNoKCRoZWFk"
	+ "LCAiKD9pKdCR0JjQmlxzKihcZHs5fSkiKQogICAgJGFjY291bnRzID0gW3JlZ2V4XTo6TWF0Y2hlcygkaGVhZCwgIig/aSnQodGHXC5ccyrihJZccyooXGR7MjB9KSIpCiAgICAkZmlyc3QgPSAoJGhlYWQgLXNwbGl0ICJgbiIpWzBdCiAg"
	+ "ICAkYmFua05hbWUgPSAoW3JlZ2V4XTo6UmVwbGFjZSgkZmlyc3QsICIoP2kpXHMq0JHQmNCaW1xzXFNdKiQiLCAiIikpLlRyaW0oKQogICAgJGNvcnIgPSBpZiAoJGFjY291bnRzLkNvdW50IC1ndCAwKSB7ICRhY2NvdW50c1swXS5Hcm91"
	+ "cHNbMV0uVmFsdWUgfSBlbHNlIHsgIiIgfQogICAgJGFjYyA9IGlmICgkYWNjb3VudHMuQ291bnQgLWd0IDEpIHsgJGFjY291bnRzWzFdLkdyb3Vwc1sxXS5WYWx1ZSB9IGVsc2UgeyAiIiB9CiAgICByZXR1cm4gQHsg0J3QsNC40LzQtdC9"
	+ "0L7QstCw0L3QuNC1ID0gJGJhbmtOYW1lOyDQkdCY0JogPSAkYmlrLkdyb3Vwc1sxXS5WYWx1ZTsg0JrQvtGA0YDQodGH0LXRgiA9ICRjb3JyOyDQoNCw0YHRh9C10YLQvdGL0LnQodGH0LXRgiA9ICRhY2MgfQp9CgpmdW5jdGlvbiBHZXQt"
	+ "TGluZXMoW3N0cmluZ10kVGV4dCkgewogICAgJHJlc3VsdCA9IEAoKQogICAgJHN0YXJ0ID0gW3JlZ2V4XTo6TWF0Y2goJFRleHQsICIoP2kp0YLQvtCy0LDRgNGLXHMqXCjRgNCw0LHQvtGC0YssXHMq0YPRgdC70YPQs9C4XCkiKQogICAg"
	+ "aWYgKC1ub3QgJHN0YXJ0LlN1Y2Nlc3MpIHsgcmV0dXJuICRyZXN1bHQgfQogICAgJHRhaWwgPSAkVGV4dC5TdWJzdHJpbmcoJHN0YXJ0LkluZGV4KQogICAgJGVuZCA9IFtyZWdleF06Ok1hdGNoKCR0YWlsLCAiKD9pbSle0LjRgtC+0LPQ"
	+ "vjoiKQogICAgJGJsb2NrID0gaWYgKCRlbmQuU3VjY2VzcykgeyAkdGFpbC5TdWJzdHJpbmcoMCwgJGVuZC5JbmRleCkgfSBlbHNlIHsgJHRhaWwgfQogICAgJHJvd3MgPSAkYmxvY2sgLXNwbGl0ICJgbiIgfCBTZWxlY3QtT2JqZWN0IC1T"
	+ "a2lwIDEKICAgICRjdXJyZW50ID0gJG51bGwKICAgIGZvcmVhY2ggKCRyYXcgaW4gJHJvd3MpIHsKICAgICAgICAkcm93ID0gJHJhdy5UcmltKCkKICAgICAgICBpZiAoLW5vdCAkcm93KSB7IGNvbnRpbnVlIH0KICAgICAgICAkbW9uZXkg"
	+ "PSBbcmVnZXhdOjpNYXRjaCgkcm93LCAiKFxkW1xkXHNdKlxkLFxkezJ9KVxzKyhcZFtcZFxzXSpcZCxcZHsyfSlccyokIikKICAgICAgICAkaGVhZCA9IFtyZWdleF06Ok1hdGNoKCRyb3csICJeKFxkezEsM30pXHMrKC4rKSQiKQogICAg"
	+ "ICAgIGlmICgkaGVhZC5TdWNjZXNzIC1hbmQgJG1vbmV5LlN1Y2Nlc3MgLWFuZCBbaW50XSRoZWFkLkdyb3Vwc1sxXS5WYWx1ZSAtbHQgNTAwKSB7CiAgICAgICAgICAgIGlmICgkbnVsbCAtbmUgJGN1cnJlbnQpIHsgJHJlc3VsdCArPSAk"
	+ "Y3VycmVudCB9CiAgICAgICAgICAgICRxdHkgPSAxLjAKICAgICAgICAgICAgJHVuaXQgPSAi0YjRgiIKICAgICAgICAgICAgJG5hbWUgPSAkaGVhZC5Hcm91cHNbMl0uVmFsdWUKICAgICAgICAgICAgJHF0eU1hdGNoID0gW3JlZ2V4XTo6"
	+ "TWF0Y2goJHJvdywgIig/aSkoXGQrKD86Wy4sXVxkKyk/KVxzKyjRiNGCfNGD0YHQu1wuP3zRh9Cw0YEoPzrQvtCyKT980LwyfNC60L7QvNC/0LtcLj8pXHMrXGRbXGRcc10qLFxkezJ9XHMrXGRbXGRcc10qLFxkezJ9XHMqJCIpCiAgICAg"
	+ "ICAgICAgIGlmICgkcXR5TWF0Y2guU3VjY2VzcykgewogICAgICAgICAgICAgICAgJHF0eSA9IFtkb3VibGVdKCgkcXR5TWF0Y2guR3JvdXBzWzFdLlZhbHVlIC1yZXBsYWNlICIsIiwgIi4iKSkKICAgICAgICAgICAgICAgICR1bml0ID0g"
	+ "JHF0eU1hdGNoLkdyb3Vwc1syXS5WYWx1ZQogICAgICAgICAgICAgICAgJG5hbWUgPSAkbmFtZS5TdWJzdHJpbmcoMCwgW01hdGhdOjpNYXgoMCwgJG5hbWUuTGVuZ3RoIC0gJHF0eU1hdGNoLkxlbmd0aCkpLlRyaW0oKQogICAgICAgICAg"
	+ "ICB9IGVsc2UgewogICAgICAgICAgICAgICAgJG5hbWUgPSBbcmVnZXhdOjpSZXBsYWNlKCRuYW1lLCAiXHMrXGRbXGRcc10qLFxkezJ9XHMrXGRbXGRcc10qLFxkezJ9XHMqJCIsICIiKS5UcmltKCkKICAgICAgICAgICAgfQogICAgICAg"
	+ "ICAgICAkY3VycmVudCA9IFtwc2N1c3RvbW9iamVjdF1AewogICAgICAgICAgICAgICAg0KHQvtC00LXRgNC20LDQvdC40LUgPSAkbmFtZQogICAgICAgICAgICAgICAg0JrQvtC70LjRh9C10YHRgtCy0L4gPSAkcXR5CiAgICAgICAgICAg"
	+ "ICAgICDQldC00LjQvdC40YbQsCA9ICR1bml0CiAgICAgICAgICAgICAgICDQptC10L3QsCA9IChDb252ZXJ0LU1vbmV5ICRtb25leS5Hcm91cHNbMV0uVmFsdWUpCiAgICAgICAgICAgICAgICDQodGD0LzQvNCwID0gKENvbnZlcnQtTW9u"
	+ "ZXkgJG1vbmV5Lkdyb3Vwc1syXS5WYWx1ZSkKICAgICAgICAgICAgfQogICAgICAgICAgICBjb250aW51ZQogICAgICAgIH0KICAgICAgICBpZiAoJG51bGwgLW5lICRjdXJyZW50KSB7CiAgICAgICAgICAgICRjdXJyZW50LtCh0L7QtNC1"
	+ "0YDQttCw0L3QuNC1ID0gKCgkY3VycmVudC7QodC+0LTQtdGA0LbQsNC90LjQtSArICIgIiArICRyb3cpIC1yZXBsYWNlICJccysiLCAiICIpLlRyaW0oKQogICAgICAgIH0KICAgIH0KICAgIGlmICgkbnVsbCAtbmUgJGN1cnJlbnQpIHsg"
	+ "JHJlc3VsdCArPSAkY3VycmVudCB9CiAgICByZXR1cm4gJHJlc3VsdAp9CgpJbnZva2UtRXh0cmFjdAoK"
	;

	Возврат ПолучитьСтрокуИзДвоичныхДанных(Base64Значение(Б64), КодировкаТекста.UTF8);

КонецФункции

Функция ТекстСкриптаДиадок()

	Б64 = "cGFyYW0oCiAgICBbUGFyYW1ldGVyKE1hbmRhdG9yeSA9ICR0cnVlKV1bc3RyaW5nXSRaaXBQYXRoLAogICAgW1BhcmFtZXRlcihNYW5kYXRvcnkgPSAkdHJ1ZSldW3N0cmluZ10kT3V0UGF0aCwKICAgIFtQYXJhbWV0ZXIoTWFuZGF0b3J5"
	+ "ID0gJHRydWUpXVtzdHJpbmddJEV4dHJhY3RTY3JpcHQKKQoKJEVycm9yQWN0aW9uUHJlZmVyZW5jZSA9ICJTdG9wIgpbU3lzdGVtLlRocmVhZGluZy5UaHJlYWRdOjpDdXJyZW50VGhyZWFkLkN1cnJlbnRDdWx0dXJlID0gW1N5c3RlbS5H"
	+ "bG9iYWxpemF0aW9uLkN1bHR1cmVJbmZvXTo6SW52YXJpYW50Q3VsdHVyZQpBZGQtVHlwZSAtQXNzZW1ibHlOYW1lIFN5c3RlbS5JTy5Db21wcmVzc2lvbgpBZGQtVHlwZSAtQXNzZW1ibHlOYW1lIFN5c3RlbS5JTy5Db21wcmVzc2lvbi5G"
	+ "aWxlU3lzdGVtCgpbU3lzdGVtLklPLkZpbGVdOjpXcml0ZUFsbFRleHQoJE91dFBhdGgsICd7ItCe0YjQuNCx0LrQsCI6ItCg0LDQt9Cx0L7RgCDQsNGA0YXQuNCy0LAg0L3QtSDQt9Cw0LLQtdGA0YjQtdC9LiJ9JywgW1N5c3RlbS5UZXh0"
	+ "LlVURjhFbmNvZGluZ106Om5ldygkZmFsc2UpKQoKZnVuY3Rpb24gU2V0LVN0cmluZ0RhdGUoJFBhcnNlZCwgW3N0cmluZ10kSXNvKSB7CiAgICBpZiAoLW5vdCAkSXNvKSB7IHJldHVybiB9CiAgICAkcHJvcCA9ICRQYXJzZWQuUFNPYmpl"
	+ "Y3QuUHJvcGVydGllc1si0JTQsNGC0LAiXQogICAgaWYgKCRwcm9wKSB7ICRQYXJzZWQuUFNPYmplY3QuUHJvcGVydGllcy5SZW1vdmUoItCU0LDRgtCwIikgfQogICAgJFBhcnNlZCB8IEFkZC1NZW1iZXIgLU5vdGVQcm9wZXJ0eU5hbWUg"
	+ "0JTQsNGC0LAgLU5vdGVQcm9wZXJ0eVZhbHVlIChbc3RyaW5nXSRJc28pCn0KCmZ1bmN0aW9uIFdyaXRlLVJlc3VsdChbb2JqZWN0XSRQYXlsb2FkKSB7CiAgICBpZiAoJFBheWxvYWQu0JTQvtC60YPQvNC10L3RgtGLKSB7CiAgICAgICAg"
	+ "Zm9yZWFjaCAoJGRvYyBpbiBAKCRQYXlsb2FkLtCU0L7QutGD0LzQtdC90YLRiykpIHsKICAgICAgICAgICAgaWYgKCRudWxsIC1lcSAkZG9jKSB7IGNvbnRpbnVlIH0KICAgICAgICAgICAgJGlzbyA9ICIiCiAgICAgICAgICAgICRjdXJy"
	+ "ZW50ID0gIiIKICAgICAgICAgICAgdHJ5IHsgJGN1cnJlbnQgPSBbc3RyaW5nXSRkb2Mu0JTQsNGC0LAgfSBjYXRjaCB7fQogICAgICAgICAgICBpZiAoJGN1cnJlbnQgLW1hdGNoICJeKFxkezR9LVxkezJ9LVxkezJ9KSQiKSB7ICRpc28g"
	+ "PSAkTWF0Y2hlc1sxXSB9CiAgICAgICAgICAgIGVsc2VpZiAoJGRvYy7QlNCw0YLQsCAtaXMgW2RhdGV0aW1lXSkgeyAkaXNvID0gJGRvYy7QlNCw0YLQsC5Ub1N0cmluZygieXl5eS1NTS1kZCIpIH0KICAgICAgICAgICAgJGZyb21OYW1l"
	+ "ID0gQ29udmVydC1OYW1lRGF0ZSAoW3N0cmluZ10kZG9jLtCY0LzRj9Ck0LDQudC70LApCiAgICAgICAgICAgIGlmICgkZnJvbU5hbWUpIHsgJGlzbyA9ICRmcm9tTmFtZSB9CiAgICAgICAgICAgIGlmICgkaXNvKSB7IFNldC1TdHJpbmdE"
	+ "YXRlICRkb2MgJGlzbyB9CiAgICAgICAgfQogICAgfQogICAgJGpzb24gPSAkUGF5bG9hZCB8IENvbnZlcnRUby1Kc29uIC1EZXB0aCA4IC1Db21wcmVzcwogICAgW1N5c3RlbS5JTy5GaWxlXTo6V3JpdGVBbGxUZXh0KCRPdXRQYXRoLCAk"
	+ "anNvbiwgW1N5c3RlbS5UZXh0LlVURjhFbmNvZGluZ106Om5ldygkZmFsc2UpKQp9CgpmdW5jdGlvbiBSZXBhaXItWmlwTmFtZShbc3RyaW5nXSROYW1lKSB7CiAgICAkYmVzdCA9ICROYW1lCiAgICAkYmVzdFNjb3JlID0gR2V0LVJ1c3Np"
	+ "YW5TY29yZSAkTmFtZQogICAgZm9yZWFjaCAoJHBhZ2UgaW4gQCgxMjUxLCA0MzcpKSB7CiAgICAgICAgdHJ5IHsKICAgICAgICAgICAgJGJ5dGVzID0gW1N5c3RlbS5UZXh0LkVuY29kaW5nXTo6R2V0RW5jb2RpbmcoJHBhZ2UpLkdldEJ5"
	+ "dGVzKCROYW1lKQogICAgICAgICAgICAkZml4ZWQgPSBbU3lzdGVtLlRleHQuRW5jb2RpbmddOjpHZXRFbmNvZGluZyg4NjYpLkdldFN0cmluZygkYnl0ZXMpCiAgICAgICAgICAgICRzY29yZSA9IEdldC1SdXNzaWFuU2NvcmUgJGZpeGVk"
	+ "CiAgICAgICAgICAgIGlmICgkc2NvcmUgLWd0ICRiZXN0U2NvcmUpIHsKICAgICAgICAgICAgICAgICRiZXN0ID0gJGZpeGVkCiAgICAgICAgICAgICAgICAkYmVzdFNjb3JlID0gJHNjb3JlCiAgICAgICAgICAgIH0KICAgICAgICB9IGNh"
	+ "dGNoIHt9CiAgICB9CiAgICByZXR1cm4gJGJlc3QKfQoKZnVuY3Rpb24gR2V0LVJ1c3NpYW5TY29yZShbc3RyaW5nXSROYW1lKSB7CiAgICBpZiAoW3N0cmluZ106OklzTnVsbE9yRW1wdHkoJE5hbWUpKSB7IHJldHVybiAwIH0KICAgICRn"
	+ "b29kID0gMAogICAgJGJhZCA9IDAKICAgIGZvcmVhY2ggKCRjaCBpbiAkTmFtZS5Ub0NoYXJBcnJheSgpKSB7CiAgICAgICAgJGNvZGUgPSBbaW50XSRjaAogICAgICAgICRpc1J1c3NpYW4gPSAoKCRjb2RlIC1nZSAweDA0MTApIC1hbmQg"
	+ "KCRjb2RlIC1sZSAweDA0NEYpKSAtb3IgKCRjb2RlIC1lcSAweDA0MDEpIC1vciAoJGNvZGUgLWVxIDB4MDQ1MSkKICAgICAgICAkaXNNb2ppYmFrZSA9ICgoJGNvZGUgLWdlIDB4MDQwMikgLWFuZCAoJGNvZGUgLWxlIDB4MDQwRikpIC1v"
	+ "ciAoKCRjb2RlIC1nZSAweDA0NTIpIC1hbmQgKCRjb2RlIC1sZSAweDA0NUYpKSAtb3IgKCgkY29kZSAtZ2UgMHgyMDEzKSAtYW5kICgkY29kZSAtbGUgMHgyMDI2KSkgLW9yICgkY29kZSAtZXEgMHgwMEFFKSAtb3IgKCRjb2RlIC1lcSAw"
	+ "eDAwQTYpIC1vciAoJGNvZGUgLWVxIDB4MDBBNykgLW9yICgkY29kZSAtZXEgMHgwMEE5KSAtb3IgKCRjb2RlIC1lcSAweDAwQUIpIC1vciAoJGNvZGUgLWVxIDB4MDBCQikgLW9yICgkY29kZSAtZXEgMHgwNDkwKSAtb3IgKCRjb2RlIC1l"
	+ "cSAweDIwQUMpIC1vciAoJGNvZGUgLWVxIDB4MjExNikgLW9yICgkY29kZSAtZXEgMHgyMTIyKQogICAgICAgIGlmICgkaXNSdXNzaWFuKSB7ICRnb29kKysgfQogICAgICAgIGVsc2VpZiAoJGlzTW9qaWJha2UpIHsgJGJhZCsrIH0KICAg"
	+ "IH0KICAgIHJldHVybiAkZ29vZCAtICgkYmFkICogMykKfQoKZnVuY3Rpb24gQ29udmVydC1Eb3REYXRlKFtzdHJpbmddJFZhbHVlKSB7CiAgICBpZiAoJFZhbHVlIC1tYXRjaCAiXihcZHsyfSlcLihcZHsyfSlcLihcZHs0fSkkIikgewog"
	+ "ICAgICAgIHJldHVybiAiezB9LXsxfS17Mn0iIC1mICRNYXRjaGVzWzNdLCAkTWF0Y2hlc1syXSwgJE1hdGNoZXNbMV0KICAgIH0KICAgIGlmICgkVmFsdWUgLW1hdGNoICJeKFxkezJ9KVwuKFxkezJ9KVwuKFxkezJ9KSQiKSB7CiAgICAg"
	+ "ICAgcmV0dXJuICIyMHswfS17MX0tezJ9IiAtZiAkTWF0Y2hlc1szXSwgJE1hdGNoZXNbMl0sICRNYXRjaGVzWzFdCiAgICB9CiAgICByZXR1cm4gIiIKfQoKZnVuY3Rpb24gR2V0LUZvbGRlcklubihbc3RyaW5nXSRQYXRoKSB7CiAgICBm"
	+ "b3JlYWNoICgkcGFydCBpbiAoJFBhdGggLXNwbGl0ICIvIikpIHsKICAgICAgICBpZiAoJHBhcnQgLW1hdGNoICJeXGR7MTB9KFxkezJ9KT8kIikgeyByZXR1cm4gJHBhcnQgfQogICAgfQogICAgcmV0dXJuICIiCn0KCmZ1bmN0aW9uIEdl"
	+ "dC1QYWNrZXQoW3N0cmluZ10kUGF0aCkgewogICAgJGRpciA9IFtTeXN0ZW0uSU8uUGF0aF06OkdldERpcmVjdG9yeU5hbWUoJFBhdGguUmVwbGFjZSgiLyIsICJcIikpCiAgICBpZiAoLW5vdCAkZGlyKSB7IHJldHVybiAkUGF0aCB9CiAg"
	+ "ICByZXR1cm4gKCRkaXIgLXJlcGxhY2UgIlxcIiwgIi8iKQp9CgpmdW5jdGlvbiBHZXQtUGFydHlOb2RlKCROb2RlKSB7CiAgICAkZW1wdHkgPSBAeyDQndCw0LjQvNC10L3QvtCy0LDQvdC40LUgPSAiIjsg0JjQndCdID0gIiI7INCa0J/Q"
	+ "nyA9ICIiOyDQkNC00YDQtdGBID0gIiIgfQogICAgaWYgKCRudWxsIC1lcSAkTm9kZSkgeyByZXR1cm4gJGVtcHR5IH0KICAgICR1bCA9ICRudWxsCiAgICAkaXAgPSAkbnVsbAogICAgdHJ5IHsgJHVsID0gJE5vZGUu0JjQtNCh0LIu0KHQ"
	+ "stCu0JvQo9GHIH0gY2F0Y2gge30KICAgIHRyeSB7ICRpcCA9ICROb2RlLtCY0LTQodCyLtCh0LLQmNCfIH0gY2F0Y2gge30KICAgIGlmICgkdWwpIHsKICAgICAgICByZXR1cm4gQHsKICAgICAgICAgICAg0J3QsNC40LzQtdC90L7QstCw"
	+ "0L3QuNC1ID0gW3N0cmluZ10kdWwu0J3QsNC40LzQntGA0LMKICAgICAgICAgICAg0JjQndCdID0gW3N0cmluZ10kdWwu0JjQndCd0K7QmwogICAgICAgICAgICDQmtCf0J8gPSBbc3RyaW5nXSR1bC7QmtCf0J8KICAgICAgICAgICAg0JDQ"
	+ "tNGA0LXRgSA9ICIiCiAgICAgICAgfQogICAgfQogICAgaWYgKCRpcCkgewogICAgICAgICRmaW8gPSAkaXAu0KTQmNCeCiAgICAgICAgJG5hbWUgPSAoQChbc3RyaW5nXSRmaW8u0KTQsNC80LjQu9C40Y8sIFtzdHJpbmddJGZpby7QmNC8"
	+ "0Y8sIFtzdHJpbmddJGZpby7QntGC0YfQtdGB0YLQstC+KSB8IFdoZXJlLU9iamVjdCB7ICRfIH0pIC1qb2luICIgIgogICAgICAgIHJldHVybiBAeyDQndCw0LjQvNC10L3QvtCy0LDQvdC40LUgPSAkbmFtZS5UcmltKCk7INCY0J3QnSA9"
	+ "IFtzdHJpbmddJGlwLtCY0J3QndCk0Js7INCa0J/QnyA9ICIiOyDQkNC00YDQtdGBID0gIiIgfQogICAgfQogICAgcmV0dXJuICRlbXB0eQp9CgpmdW5jdGlvbiBHZXQtQXR0clRleHQoJE5vZGUsIFtzdHJpbmddJE5hbWUpIHsKICAgIGlm"
	+ "ICgkbnVsbCAtZXEgJE5vZGUpIHsgcmV0dXJuICIiIH0KICAgICR2YWx1ZSA9ICROb2RlLkdldEF0dHJpYnV0ZSgkTmFtZSkKICAgIGlmICgkdmFsdWUpIHsgcmV0dXJuIFtzdHJpbmddJHZhbHVlIH0KICAgICRwcm9wID0gJE5vZGUuJE5h"
	+ "bWUKICAgIGlmICgkcHJvcCkgeyByZXR1cm4gW3N0cmluZ10kcHJvcCB9CiAgICByZXR1cm4gIiIKfQoKZnVuY3Rpb24gUmVhZC1VcGRYbWwoW3N0cmluZ10kRmlsZSwgW3N0cmluZ10kUGFja2V0LCBbc3RyaW5nXSRGb2xkZXJJbm4pIHsK"
	+ "ICAgICR0ZXh0ID0gW1N5c3RlbS5UZXh0LkVuY29kaW5nXTo6R2V0RW5jb2RpbmcoMTI1MSkuR2V0U3RyaW5nKFtTeXN0ZW0uSU8uRmlsZV06OlJlYWRBbGxCeXRlcygkRmlsZSkpCiAgICBbeG1sXSR4bWwgPSAkdGV4dAogICAgJGRvYyA9"
	+ "ICR4bWwu0KTQsNC50Lsu0JTQvtC60YPQvNC10L3RggogICAgJHNmID0gJGRvYy7QodCy0KHRh9Ck0LDQutGCCiAgICAkc2VsbGVyID0gR2V0LVBhcnR5Tm9kZSAkc2Yu0KHQstCf0YDQvtC0CiAgICAkYnV5ZXIgPSBHZXQtUGFydHlOb2Rl"
	+ "ICRzZi7QodCy0J/QvtC60YPQvwogICAgJGJhbmtOb2RlID0gJG51bGwKICAgIHRyeSB7ICRiYW5rTm9kZSA9ICRzZi7QodCy0J/RgNC+0LQu0JHQsNC90LrQoNC10LrQsiB9IGNhdGNoIHt9CiAgICAkYmFuayA9IEB7INCd0LDQuNC80LXQ"
	+ "vdC+0LLQsNC90LjQtSA9ICIiOyDQkdCY0JogPSAiIjsg0JrQvtGA0YDQodGH0LXRgiA9ICIiOyDQoNCw0YHRh9C10YLQvdGL0LnQodGH0LXRgiA9ICIiIH0KICAgIGlmICgkYmFua05vZGUpIHsKICAgICAgICAkc3YgPSAkYmFua05vZGUu"
	+ "0KHQstCR0LDQvdC6CiAgICAgICAgJGJhbmsgPSBAewogICAgICAgICAgICDQndCw0LjQvNC10L3QvtCy0LDQvdC40LUgPSBbc3RyaW5nXSRzdi7QndCw0LjQvNCR0LDQvdC6CiAgICAgICAgICAgINCR0JjQmiA9IFtzdHJpbmddJHN2LtCR"
	+ "0JjQmgogICAgICAgICAgICDQmtC+0YDRgNCh0YfQtdGCID0gW3N0cmluZ10kc3Yu0JrQvtGA0KHRh9C10YIKICAgICAgICAgICAg0KDQsNGB0YfQtdGC0L3Ri9C50KHRh9C10YIgPSBbc3RyaW5nXSRiYW5rTm9kZS7QndC+0LzQtdGA0KHR"
	+ "h9C10YLQsAogICAgICAgIH0KICAgIH0KICAgICRsaW5lcyA9IE5ldy1PYmplY3QgU3lzdGVtLkNvbGxlY3Rpb25zLkdlbmVyaWMuTGlzdFtvYmplY3RdCiAgICAkZ29vZHMgPSBAKCkKICAgIHRyeSB7ICRnb29kcyA9IEAoJGRvYy7QotCw"
	+ "0LHQu9Ch0YfQpNCw0LrRgi7QodCy0LXQtNCi0L7QsikgfSBjYXRjaCB7fQogICAgZm9yZWFjaCAoJHJvdyBpbiAkZ29vZHMpIHsKICAgICAgICBpZiAoJG51bGwgLWVxICRyb3cgLW9yIC1ub3QgJHJvdy7QndCw0LjQvNCi0L7QsikgeyBj"
	+ "b250aW51ZSB9CiAgICAgICAgJHF0eSA9IDEuMAogICAgICAgIGlmICgkcm93LtCa0L7Qu9Ci0L7QsikgeyAkcXR5ID0gW2RvdWJsZV0kcm93LtCa0L7Qu9Ci0L7QsiB9CiAgICAgICAgJGdyb3NzID0gMC4wCiAgICAgICAgaWYgKCRyb3cu"
	+ "0KHRgtCi0L7QstCj0YfQndCw0LspIHsgJGdyb3NzID0gW2RvdWJsZV0kcm93LtCh0YLQotC+0LLQo9GH0J3QsNC7IH0KICAgICAgICAkcHJpY2UgPSAkZ3Jvc3MKICAgICAgICBpZiAoJHF0eSAtbmUgMCkgeyAkcHJpY2UgPSBbbWF0aF06"
	+ "OlJvdW5kKCRncm9zcyAvICRxdHksIDIpIH0KICAgICAgICAkbGluZXMuQWRkKFtwc2N1c3RvbW9iamVjdF1AewogICAgICAgICAgICDQodC+0LTQtdGA0LbQsNC90LjQtSA9IFtzdHJpbmddJHJvdy7QndCw0LjQvNCi0L7QsgogICAgICAg"
	+ "ICAgICDQmtC+0LvQuNGH0LXRgdGC0LLQviA9ICRxdHkKICAgICAgICAgICAg0JXQtNC40L3QuNGG0LAgPSBbc3RyaW5nXSRyb3cu0J3QsNC40LzQldC00JjQt9C8CiAgICAgICAgICAgINCm0LXQvdCwID0gJHByaWNlCiAgICAgICAgICAg"
	+ "INCh0YPQvNC80LAgPSBbbWF0aF06OlJvdW5kKCRncm9zcywgMikKICAgICAgICB9KQogICAgfQogICAgJHRvdGFsID0gMC4wCiAgICAkbmV0ID0gMC4wCiAgICB0cnkgeyAkdG90YWwgPSBbZG91YmxlXSRkb2Mu0KLQsNCx0LvQodGH0KTQ"
	+ "sNC60YIu0JLRgdC10LPQvtCe0L/Quy7QodGC0KLQvtCy0KPRh9Cd0LDQu9CS0YHQtdCz0L4gfSBjYXRjaCB7fQogICAgdHJ5IHsgJG5ldCA9IFtkb3VibGVdJGRvYy7QotCw0LHQu9Ch0YfQpNCw0LrRgi7QktGB0LXQs9C+0J7Qv9C7LtCh"
	+ "0YLQotC+0LLQkdC10LfQndCU0KHQktGB0LXQs9C+IH0gY2F0Y2gge30KICAgIGlmICgkdG90YWwgLWVxIDApIHsgZm9yZWFjaCAoJGxpbmUgaW4gJGxpbmVzKSB7ICR0b3RhbCArPSAkbGluZS7QodGD0LzQvNCwIH0gfQogICAgJHZhdFN1"
	+ "bSA9IFttYXRoXTo6Um91bmQoJHRvdGFsIC0gJG5ldCwgMikKICAgIGlmICgkdmF0U3VtIC1sdCAwKSB7ICR2YXRTdW0gPSAwIH0KICAgICRyYXRlID0gMAogICAgJHJhdGVUZXh0ID0gIiIKICAgIGlmICgkZ29vZHMuQ291bnQgLWd0IDAp"
	+ "IHsgJHJhdGVUZXh0ID0gW3N0cmluZ10kZ29vZHNbMF0u0J3QsNC70KHRgiB9CiAgICBpZiAoJHJhdGVUZXh0IC1tYXRjaCAiKFxkKykiKSB7ICRyYXRlID0gW2ludF0kTWF0Y2hlc1sxXSB9CiAgICAkYmFzaXMgPSAiIgogICAgJGNvbnRy"
	+ "YWN0Tm8gPSAiIgogICAgJGNvbnRyYWN0RGF0ZSA9ICIiCiAgICAkcGVyID0gJG51bGwKICAgIHRyeSB7ICRwZXIgPSAkZG9jLtCh0LLQn9GA0L7QtNCf0LXRgC7QodCy0J/QtdGAIH0gY2F0Y2gge30KICAgIGlmICgtbm90ICRwZXIpIHsg"
	+ "dHJ5IHsgJHBlciA9ICRkb2Mu0KHQstCf0LXRgCB9IGNhdGNoIHt9IH0KICAgIGlmICgkcGVyKSB7CiAgICAgICAgJG9zbiA9IEAoJHBlci7QntGB0L3Qn9C10YApIHwgU2VsZWN0LU9iamVjdCAtRmlyc3QgMQogICAgICAgIGlmICgkb3Nu"
	+ "KSB7CiAgICAgICAgICAgICRiYXNpcyA9IFtzdHJpbmddJG9zbi7QoNC10LrQstCd0LDQuNC80JTQvtC6CiAgICAgICAgICAgICRjb250cmFjdE5vID0gW3N0cmluZ10kb3NuLtCg0LXQutCy0J3QvtC80LXRgNCU0L7QugogICAgICAgICAg"
	+ "ICAkY29udHJhY3REYXRlID0gQ29udmVydC1Eb3REYXRlIChbc3RyaW5nXSRvc24u0KDQtdC60LLQlNCw0YLQsNCU0L7QuikKICAgICAgICB9CiAgICB9CiAgICAkZG9jSWQgPSAiIgogICAgdHJ5IHsKICAgICAgICBmb3JlYWNoICgkaW5m"
	+ "byBpbiBAKCRzZi7QmNC90YTQn9C+0LvQpNCl0JYxLtCi0LXQutGB0YLQmNC90YQpKSB7CiAgICAgICAgICAgIGlmIChbc3RyaW5nXSRpbmZvLtCY0LTQtdC90YLQuNGEIC1lcSAi0JjQtNC10L3RgtC40YTQuNC60LDRgtC+0YDQlNC+0LrR"
	+ "g9C80LXQvdGC0LDQntGB0L3QvtCy0LDQvdC40Y8iKSB7CiAgICAgICAgICAgICAgICAkZG9jSWQgPSBbc3RyaW5nXSRpbmZvLtCX0L3QsNGH0LXQvQogICAgICAgICAgICB9CiAgICAgICAgfQogICAgfSBjYXRjaCB7fQogICAgJHBheU5v"
	+ "ID0gIiIKICAgICRwYXlEYXRlID0gIiIKICAgIHRyeSB7CiAgICAgICAgJHBheSA9IEAoJHNmLtCh0LLQn9Cg0JQpIHwgU2VsZWN0LU9iamVjdCAtRmlyc3QgMQogICAgICAgIGlmICgkcGF5KSB7CiAgICAgICAgICAgICRwYXlObyA9IFtz"
	+ "dHJpbmddJHBheS7QndC+0LzQtdGA0J/QoNCUCiAgICAgICAgICAgICRwYXlEYXRlID0gQ29udmVydC1Eb3REYXRlIChbc3RyaW5nXSRwYXku0JTQsNGC0LDQn9Cg0JQpCiAgICAgICAgfQogICAgfSBjYXRjaCB7fQogICAgcmV0dXJuIFtw"
	+ "c2N1c3RvbW9iamVjdF1AewogICAgICAgINCS0LjQtCA9ICLQo9Cf0JQiCiAgICAgICAg0JjRgdGC0L7Rh9C90LjQuiA9ICJYTUwiCiAgICAgICAg0J3QvtC80LXRgCA9IFtzdHJpbmddJHNmLtCd0L7QvNC10YDQlNC+0LoKICAgICAgICDQ"
	+ "lNCw0YLQsCA9IChDb252ZXJ0LURvdERhdGUgKFtzdHJpbmddJHNmLtCU0LDRgtCw0JTQvtC6KSkKICAgICAgICDQmNC0ID0gJGRvY0lkCiAgICAgICAg0J/QvtGB0YLQsNCy0YnQuNC6ID0gJHNlbGxlcgogICAgICAgINCf0L7QutGD0L/Q"
	+ "sNGC0LXQu9GMID0gJGJ1eWVyCiAgICAgICAg0J7RgdC90L7QstCw0L3QuNC1ID0gJGJhc2lzCiAgICAgICAg0JTQvtCz0L7QstC+0YDQndC+0LzQtdGAID0gJGNvbnRyYWN0Tm8KICAgICAgICDQlNC+0LPQvtCy0L7RgNCU0LDRgtCwID0g"
	+ "JGNvbnRyYWN0RGF0ZQogICAgICAgINCf0LvQsNGC0LXQttC60LDQndC+0LzQtdGAID0gJHBheU5vCiAgICAgICAg0J/Qu9Cw0YLQtdC20LrQsNCU0LDRgtCwID0gJHBheURhdGUKICAgICAgICDQkdCw0L3QuiA9ICRiYW5rCiAgICAgICAg"
	+ "0KHRgtGA0L7QutC4ID0gQCgkbGluZXMuVG9BcnJheSgpKQogICAgICAgINCh0YPQvNC80LAgPSBbbWF0aF06OlJvdW5kKCR0b3RhbCwgMikKICAgICAgICDQodGC0LDQstC60LDQndCU0KEgPSAkcmF0ZQogICAgICAgINCh0YPQvNC80LDQ"
	+ "ndCU0KEgPSAkdmF0U3VtCiAgICAgICAg0KHRg9C80LzQsNCS0LrQu9GO0YfQsNC10YLQndCU0KEgPSAkdHJ1ZQogICAgICAgINCf0LDQutC10YIgPSAkUGFja2V0CiAgICAgICAg0JjQndCd0J/QsNC/0LrQuCA9ICRGb2xkZXJJbm4KICAg"
	+ "ICAgICDQmNC80Y/QpNCw0LnQu9CwID0gW1N5c3RlbS5JTy5QYXRoXTo6R2V0RmlsZU5hbWUoJEZpbGUpCiAgICAgICAg0J/RgNC10LTRg9C/0YDQtdC20LTQtdC90LjRjyA9IEAoKQogICAgfQp9CgpmdW5jdGlvbiBDb252ZXJ0LU5hbWVE"
	+ "YXRlKFtzdHJpbmddJE5hbWUpIHsKICAgIGlmIChbc3RyaW5nXTo6SXNOdWxsT3JXaGl0ZVNwYWNlKCROYW1lKSkgeyByZXR1cm4gIiIgfQogICAgJG5vcm0gPSAkTmFtZS5Ub0xvd2VyKCkuUmVwbGFjZSgiXyIsICIgIikKICAgICRwb3Mg"
	+ "PSAkbm9ybS5JbmRleE9mKCIg0L7RgiAiKQogICAgaWYgKCRwb3MgLWx0IDApIHsgcmV0dXJuICIiIH0KICAgICR0YWlsID0gJG5vcm0uU3Vic3RyaW5nKCRwb3MgKyA0KS5UcmltKCkKICAgICRkb3R0ZWQgPSBbcmVnZXhdOjpNYXRjaCgk"
	+ "dGFpbCwgIl4oXGR7MSwyfSlcLihcZHsxLDJ9KVwuKFxkezIsNH0pIikKICAgICRkYXkgPSAwCiAgICAkbW9udGggPSAwCiAgICAkeWVhciA9IDAKICAgIGlmICgkZG90dGVkLlN1Y2Nlc3MpIHsKICAgICAgICBbdm9pZF1baW50XTo6VHJ5"
	+ "UGFyc2UoJGRvdHRlZC5Hcm91cHNbMV0uVmFsdWUsIFtyZWZdJGRheSkKICAgICAgICBbdm9pZF1baW50XTo6VHJ5UGFyc2UoJGRvdHRlZC5Hcm91cHNbMl0uVmFsdWUsIFtyZWZdJG1vbnRoKQogICAgICAgIFt2b2lkXVtpbnRdOjpUcnlQ"
	+ "YXJzZSgkZG90dGVkLkdyb3Vwc1szXS5WYWx1ZSwgW3JlZl0keWVhcikKICAgIH0gZWxzZSB7CiAgICAgICAgJGRheU1hdGNoID0gW3JlZ2V4XTo6TWF0Y2goJHRhaWwsICJeKFxkezEsMn0pIikKICAgICAgICBpZiAoLW5vdCAkZGF5TWF0"
	+ "Y2guU3VjY2VzcykgeyByZXR1cm4gIiIgfQogICAgICAgIFt2b2lkXVtpbnRdOjpUcnlQYXJzZSgkZGF5TWF0Y2guR3JvdXBzWzFdLlZhbHVlLCBbcmVmXSRkYXkpCiAgICAgICAgJHN0ZW1zID0gQCgKICAgICAgICAgICAgQCgi0Y/QvdCy"
	+ "0LDRgCIsIDEpLCBAKCLRhNC10LLRgNCw0LsiLCAyKSwgQCgi0LzQsNGA0YIiLCAzKSwgQCgi0LDQv9GA0LXQuyIsIDQpLCBAKCLQvNCw0Y8iLCA1KSwgQCgi0LzQsNC5IiwgNSksCiAgICAgICAgICAgIEAoItC40Y7QvSIsIDYpLCBAKCLQ"
	+ "uNGO0LsiLCA3KSwgQCgi0LDQstCz0YPRgdGCIiwgOCksIEAoItGB0LXQvdGC0Y/QsdGAIiwgOSksIEAoItC+0LrRgtGP0LHRgCIsIDEwKSwgQCgi0L3QvtGP0LHRgCIsIDExKSwgQCgi0LTQtdC60LDQsdGAIiwgMTIpCiAgICAgICAgKQog"
	+ "ICAgICAgIGZvcmVhY2ggKCRzdGVtIGluICRzdGVtcykgewogICAgICAgICAgICBpZiAoJHRhaWwuQ29udGFpbnMoW3N0cmluZ10kc3RlbVswXSkpIHsgJG1vbnRoID0gW2ludF0kc3RlbVsxXTsgYnJlYWsgfQogICAgICAgIH0KICAgICAg"
	+ "ICAkeWVhck1hdGNoID0gW3JlZ2V4XTo6TWF0Y2goJHRhaWwsICIoMjBcZHsyfSkiKQogICAgICAgIGlmICgkeWVhck1hdGNoLlN1Y2Nlc3MpIHsgW3ZvaWRdW2ludF06OlRyeVBhcnNlKCR5ZWFyTWF0Y2guR3JvdXBzWzFdLlZhbHVlLCBb"
	+ "cmVmXSR5ZWFyKSB9CiAgICB9CiAgICBpZiAoJHllYXIgLWx0IDEwMCkgeyAkeWVhciArPSAyMDAwIH0KICAgIGlmICgkeWVhciAtbHQgMjAwMCAtb3IgJG1vbnRoIC1sdCAxIC1vciAkbW9udGggLWd0IDEyIC1vciAkZGF5IC1sdCAxIC1v"
	+ "ciAkZGF5IC1ndCAzMSkgeyByZXR1cm4gIiIgfQogICAgcmV0dXJuICJ7MDowMDAwfS17MTowMH0tezI6MDB9IiAtZiAkeWVhciwgJG1vbnRoLCAkZGF5Cn0KCmZ1bmN0aW9uIENvbXBsZXRlLVBhcnNlZCgkUGFyc2VkLCBbc3RyaW5nXSRG"
	+ "b2xkZXJJbm4sIFtzdHJpbmddJExlYWYpIHsKICAgIGlmICgkbnVsbCAtZXEgJFBhcnNlZC7Qn9C+0YHRgtCw0LLRidC40LopIHsKICAgICAgICAkUGFyc2VkIHwgQWRkLU1lbWJlciAtTm90ZVByb3BlcnR5TmFtZSDQn9C+0YHRgtCw0LLR"
	+ "idC40LogLU5vdGVQcm9wZXJ0eVZhbHVlIChbcHNjdXN0b21vYmplY3RdQHsg0J3QsNC40LzQtdC90L7QstCw0L3QuNC1ID0gItCe0J7QniDQmtCQ0J3QntCdIjsg0JjQndCdID0gIjc3MTc1NTI3ODQiOyDQmtCf0J8gPSAiNzcxNzAxMDAx"
	+ "Ijsg0JDQtNGA0LXRgSA9ICIiIH0pIC1Gb3JjZQogICAgfSBlbHNlaWYgKC1ub3QgW3N0cmluZ10kUGFyc2VkLtCf0L7RgdGC0LDQstGJ0LjQui7QmNCd0J0pIHsKICAgICAgICAkUGFyc2VkLtCf0L7RgdGC0LDQstGJ0LjQuiB8IEFkZC1N"
	+ "ZW1iZXIgLU5vdGVQcm9wZXJ0eU5hbWUg0JjQndCdIC1Ob3RlUHJvcGVydHlWYWx1ZSAiNzcxNzU1Mjc4NCIgLUZvcmNlCiAgICB9CiAgICAkc2VsbGVyID0gW3N0cmluZ10kUGFyc2VkLtCf0L7RgdGC0LDQstGJ0LjQui7QmNCd0J0KICAg"
	+ "ICRidXllcklubiA9ICIiCiAgICB0cnkgeyAkYnV5ZXJJbm4gPSBbc3RyaW5nXSRQYXJzZWQu0J/QvtC60YPQv9Cw0YLQtdC70Ywu0JjQndCdIH0gY2F0Y2gge30KICAgIGlmICgtbm90ICRidXllcklubiAtYW5kICRGb2xkZXJJbm4gLW1h"
	+ "dGNoICJeXGR7MTB9KFxkezJ9KT8kIiAtYW5kICRGb2xkZXJJbm4gLW5lICRzZWxsZXIpIHsKICAgICAgICBpZiAoJG51bGwgLWVxICRQYXJzZWQu0J/QvtC60YPQv9Cw0YLQtdC70YwpIHsKICAgICAgICAgICAgJFBhcnNlZCB8IEFkZC1N"
	+ "ZW1iZXIgLU5vdGVQcm9wZXJ0eU5hbWUg0J/QvtC60YPQv9Cw0YLQtdC70YwgLU5vdGVQcm9wZXJ0eVZhbHVlIChbcHNjdXN0b21vYmplY3RdQHsg0J3QsNC40LzQtdC90L7QstCw0L3QuNC1ID0gKCLQmNCd0J0gIiArICRGb2xkZXJJbm4p"
	+ "OyDQmNCd0J0gPSAkRm9sZGVySW5uOyDQmtCf0J8gPSAiIjsg0JDQtNGA0LXRgSA9ICIiIH0pIC1Gb3JjZQogICAgICAgIH0gZWxzZSB7CiAgICAgICAgICAgICRQYXJzZWQu0J/QvtC60YPQv9Cw0YLQtdC70YwgfCBBZGQtTWVtYmVyIC1O"
	+ "b3RlUHJvcGVydHlOYW1lINCY0J3QnSAtTm90ZVByb3BlcnR5VmFsdWUgJEZvbGRlcklubiAtRm9yY2UKICAgICAgICAgICAgaWYgKC1ub3QgW3N0cmluZ10kUGFyc2VkLtCf0L7QutGD0L/QsNGC0LXQu9GMLtCd0LDQuNC80LXQvdC+0LLQ"
	+ "sNC90LjQtSkgewogICAgICAgICAgICAgICAgJFBhcnNlZC7Qn9C+0LrRg9C/0LDRgtC10LvRjCB8IEFkZC1NZW1iZXIgLU5vdGVQcm9wZXJ0eU5hbWUg0J3QsNC40LzQtdC90L7QstCw0L3QuNC1IC1Ob3RlUHJvcGVydHlWYWx1ZSAoItCY"
	+ "0J3QnSAiICsgJEZvbGRlcklubikgLUZvcmNlCiAgICAgICAgICAgIH0KICAgICAgICB9CiAgICB9CiAgICBpZiAoLW5vdCBbc3RyaW5nXSRQYXJzZWQu0J3QvtC80LXRgCkgewogICAgICAgICRudW1iZXIgPSBbcmVnZXhdOjpNYXRjaCgk"
	+ "TGVhZiwgIlvihJZOXVtfXHNdKihbMC05QS1aYS160JAt0K/QsC3Rj9CB0ZFcLS9dKykiKQogICAgICAgIGlmICgkbnVtYmVyLlN1Y2Nlc3MpIHsKICAgICAgICAgICAgJFBhcnNlZCB8IEFkZC1NZW1iZXIgLU5vdGVQcm9wZXJ0eU5hbWUg"
	+ "0J3QvtC80LXRgCAtTm90ZVByb3BlcnR5VmFsdWUgJG51bWJlci5Hcm91cHNbMV0uVmFsdWUgLUZvcmNlCiAgICAgICAgfQogICAgfQogICAgaWYgKFtzdHJpbmddJFBhcnNlZC7QlNCw0YLQsCAtbm90bWF0Y2ggIl5cZHs0fS1cZHsyfS1c"
	+ "ZHsyfSQiKSB7CiAgICAgICAgJGZyb21OYW1lID0gQ29udmVydC1OYW1lRGF0ZSAkTGVhZgogICAgICAgIGlmICgkZnJvbU5hbWUpIHsKICAgICAgICAgICAgJFBhcnNlZCB8IEFkZC1NZW1iZXIgLU5vdGVQcm9wZXJ0eU5hbWUg0JTQsNGC"
	+ "0LAgLU5vdGVQcm9wZXJ0eVZhbHVlICRmcm9tTmFtZSAtRm9yY2UKICAgICAgICB9CiAgICB9Cn0KCmZ1bmN0aW9uIFJlYWQtUGRmSnNvbihbc3RyaW5nXSRGaWxlLCBbc3RyaW5nXSRUaXRsZSkgewogICAgJGpzb25QYXRoID0gW1N5c3Rl"
	+ "bS5JTy5QYXRoXTo6Q2hhbmdlRXh0ZW5zaW9uKCRGaWxlLCAiLmpzb24iKQogICAgJHNhZmVUaXRsZSA9ICIiCiAgICBpZiAoJFRpdGxlKSB7ICRzYWZlVGl0bGUgPSAkVGl0bGUuUmVwbGFjZSgnIicsICIgIikgfQogICAgJGFyZ3VtZW50"
	+ "cyA9ICItTm9Qcm9maWxlIC1Ob25JbnRlcmFjdGl2ZSAtRXhlY3V0aW9uUG9saWN5IEJ5cGFzcyAtRmlsZSBgIiRFeHRyYWN0U2NyaXB0YCIgLVBkZlBhdGggYCIkRmlsZWAiIC1PdXRQYXRoIGAiJGpzb25QYXRoYCIgLVRpdGxlIGAiJHNh"
	+ "ZmVUaXRsZWAiIgogICAgJHBzaSA9IE5ldy1PYmplY3QgU3lzdGVtLkRpYWdub3N0aWNzLlByb2Nlc3NTdGFydEluZm8KICAgICRwc2kuRmlsZU5hbWUgPSAicG93ZXJzaGVsbC5leGUiCiAgICAkcHNpLkFyZ3VtZW50cyA9ICRhcmd1bWVu"
	+ "dHMKICAgICRwc2kuVXNlU2hlbGxFeGVjdXRlID0gJGZhbHNlCiAgICAkcHNpLkNyZWF0ZU5vV2luZG93ID0gJHRydWUKICAgICRwcm9jZXNzID0gW1N5c3RlbS5EaWFnbm9zdGljcy5Qcm9jZXNzXTo6U3RhcnQoJHBzaSkKICAgIGlmICgt"
	+ "bm90ICRwcm9jZXNzLldhaXRGb3JFeGl0KDE4MDAwMCkpIHsKICAgICAgICB0cnkgeyAkcHJvY2Vzcy5LaWxsKCkgfSBjYXRjaCB7fQogICAgICAgIHJldHVybiAkbnVsbAogICAgfQogICAgaWYgKC1ub3QgKFRlc3QtUGF0aCAkanNvblBh"
	+ "dGgpKSB7IHJldHVybiAkbnVsbCB9CiAgICAkcmF3ID0gW1N5c3RlbS5JTy5GaWxlXTo6UmVhZEFsbFRleHQoJGpzb25QYXRoLCBbU3lzdGVtLlRleHQuVVRGOEVuY29kaW5nXTo6bmV3KCRmYWxzZSkpCiAgICBpZiAoW3N0cmluZ106Oklz"
	+ "TnVsbE9yV2hpdGVTcGFjZSgkcmF3KSkgeyByZXR1cm4gJG51bGwgfQogICAgcmV0dXJuICRyYXcgfCBDb252ZXJ0RnJvbS1Kc29uCn0KCiR3b3JrID0gSm9pbi1QYXRoIChbU3lzdGVtLklPLlBhdGhdOjpHZXRUZW1wUGF0aCgpKSAoInpz"
	+ "ZGlhZG9jXyIgKyBbZ3VpZF06Ok5ld0d1aWQoKS5Ub1N0cmluZygiTiIpKQpOZXctSXRlbSAtSXRlbVR5cGUgRGlyZWN0b3J5IC1QYXRoICR3b3JrIHwgT3V0LU51bGwKJGRvY3MgPSBOZXctT2JqZWN0IFN5c3RlbS5Db2xsZWN0aW9ucy5H"
	+ "ZW5lcmljLkxpc3Rbb2JqZWN0XQokeG1sS2V5cyA9IEB7fQoKdHJ5IHsKICAgICR6aXAgPSBbU3lzdGVtLklPLkNvbXByZXNzaW9uLlppcEZpbGVdOjpPcGVuUmVhZCgkWmlwUGF0aCkKICAgIHRyeSB7CiAgICAgICAgJGluZGV4ID0gMAog"
	+ "ICAgICAgIGZvcmVhY2ggKCRlbnRyeSBpbiAkemlwLkVudHJpZXMpIHsKICAgICAgICAgICAgaWYgKC1ub3QgJGVudHJ5Lk5hbWUpIHsgY29udGludWUgfQogICAgICAgICAgICAkZnVsbCA9IFJlcGFpci1aaXBOYW1lICgkZW50cnkuRnVs"
	+ "bE5hbWUuUmVwbGFjZSgiXCIsICIvIikpCiAgICAgICAgICAgICRsZWFmID0gW1N5c3RlbS5JTy5QYXRoXTo6R2V0RmlsZU5hbWUoJGZ1bGwpCiAgICAgICAgICAgICRsb3cgPSAkbGVhZi5Ub0xvd2VyKCkKICAgICAgICAgICAgJGtlZXAg"
	+ "PSAkZmFsc2UKICAgICAgICAgICAgaWYgKCRsb3cgLWxpa2UgIm9uX25zY2hmZG9wcHIqLnhtbCIpIHsgJGtlZXAgPSAkdHJ1ZSB9CiAgICAgICAgICAgIGVsc2VpZiAoJGxvdy5FbmRzV2l0aCgiLnBkZiIpIC1vciAkbG93LkVuZHNXaXRo"
	+ "KCIuZG9jeCIpIC1vciAkbG93LkVuZHNXaXRoKCIuZG9jIikpIHsKICAgICAgICAgICAgICAgIGlmICgkbG93IC1saWtlICIq0L/RgNC+0YLQvtC60L7QuyoiKSB7ICRrZWVwID0gJGZhbHNlIH0KICAgICAgICAgICAgICAgIGVsc2VpZiAo"
	+ "JGxvdyAtbGlrZSAi0L/QtdGH0LDRgtC90LDRjyDRhNC+0YDQvNCwKiIpIHsgJGtlZXAgPSAkZmFsc2UgfQogICAgICAgICAgICAgICAgZWxzZSB7ICRrZWVwID0gJHRydWUgfQogICAgICAgICAgICB9CiAgICAgICAgICAgIGlmICgtbm90"
	+ "ICRrZWVwKSB7IGNvbnRpbnVlIH0KICAgICAgICAgICAgdHJ5IHsKICAgICAgICAgICAgJGluZGV4KysKICAgICAgICAgICAgJGV4dCA9IFtTeXN0ZW0uSU8uUGF0aF06OkdldEV4dGVuc2lvbigkbGVhZikKICAgICAgICAgICAgJHRhcmdl"
	+ "dCA9IEpvaW4tUGF0aCAkd29yayAoInswOjAwMDB9ezF9IiAtZiAkaW5kZXgsICRleHQpCiAgICAgICAgICAgICRlbnRyeVN0cmVhbSA9ICRlbnRyeS5PcGVuKCkKICAgICAgICAgICAgJG91dHB1dCA9IFtTeXN0ZW0uSU8uRmlsZV06OkNy"
	+ "ZWF0ZSgkdGFyZ2V0KQogICAgICAgICAgICB0cnkgeyAkZW50cnlTdHJlYW0uQ29weVRvKCRvdXRwdXQpIH0gZmluYWxseSB7ICRvdXRwdXQuRGlzcG9zZSgpOyAkZW50cnlTdHJlYW0uRGlzcG9zZSgpIH0KICAgICAgICAgICAgJHBhY2tl"
	+ "dCA9IEdldC1QYWNrZXQgJGZ1bGwKICAgICAgICAgICAgJGZvbGRlcklubiA9IEdldC1Gb2xkZXJJbm4gJGZ1bGwKICAgICAgICAgICAgaWYgKCRsb3cgLWxpa2UgIm9uX25zY2hmZG9wcHIqLnhtbCIpIHsKICAgICAgICAgICAgICAgIHRy"
	+ "eSB7CiAgICAgICAgICAgICAgICAgICAgJHVwZCA9IFJlYWQtVXBkWG1sICR0YXJnZXQgJHBhY2tldCAkZm9sZGVySW5uCiAgICAgICAgICAgICAgICAgICAgJHVwZCB8IEFkZC1NZW1iZXIgLU5vdGVQcm9wZXJ0eU5hbWUg0JjQvNGP0KTQ"
	+ "sNC50LvQsCAtTm90ZVByb3BlcnR5VmFsdWUgJGxlYWYgLUZvcmNlCiAgICAgICAgICAgICAgICAgICAgJGtleSA9ICgkcGFja2V0ICsgInwiICsgJHVwZC7QndC+0LzQtdGAKS5Ub0xvd2VyKCkKICAgICAgICAgICAgICAgICAgICAkeG1s"
	+ "S2V5c1ska2V5XSA9ICR0cnVlCiAgICAgICAgICAgICAgICAgICAgJGRvY3MuQWRkKCR1cGQpCiAgICAgICAgICAgICAgICB9IGNhdGNoIHsKICAgICAgICAgICAgICAgICAgICAkZG9jcy5BZGQoW3BzY3VzdG9tb2JqZWN0XUB7INCS0LjQ"
	+ "tCA9ICLQn9GA0L7Rh9C10LUiOyDQmNC80Y/QpNCw0LnQu9CwID0gJGxlYWY7INCf0LDQutC10YIgPSAkcGFja2V0OyDQn9GA0LjRh9C40L3QsCA9ICRfLkV4Y2VwdGlvbi5NZXNzYWdlIH0pCiAgICAgICAgICAgICAgICB9CiAgICAgICAg"
	+ "ICAgICAgICBjb250aW51ZQogICAgICAgICAgICB9CiAgICAgICAgICAgICRraW5kID0gItCf0YDQvtGH0LXQtSIKICAgICAgICAgICAgaWYgKCRsb3cgLW1hdGNoICLRgdGH0LXRgltcc19dKtC90LBbXHNfXSrQvtC/0LvQsNGC0YN80YHR"
	+ "h9GR0YJbXHNfXSrQvdCwW1xzX10q0L7Qv9C70LDRgtGDIikgeyAka2luZCA9ICLQodGH0LXRgiIgfQogICAgICAgICAgICBlbHNlaWYgKCRsb3cgLW1hdGNoICLRg9C/0LR80YHRh9C10YIt0YTQsNC60YLRg9GA0LB80YHRh9GR0YIt0YTQ"
	+ "sNC60YLRg9GA0LB80YHRh9GE0LTQvtC/IikgeyAka2luZCA9ICLQo9Cf0JQiIH0KICAgICAgICAgICAgZWxzZWlmICgkbG93IC1tYXRjaCAi0LDQutGCXHMq0YHQstC10YDQutC4IikgeyAka2luZCA9ICLQkNC60YLQodCy0LXRgNC60Lgi"
	+ "IH0KICAgICAgICAgICAgZWxzZWlmICgkbG93IC1tYXRjaCAi0LTQvtCy0LXRgNC10L0iKSB7ICRraW5kID0gItCU0L7QstC10YDQtdC90L3QvtGB0YLRjCIgfQogICAgICAgICAgICBlbHNlaWYgKCRsb3cgLW1hdGNoICLQt9Cw0Y/QstC6"
	+ "IikgeyAka2luZCA9ICLQl9Cw0Y/QstC60LAiIH0KICAgICAgICAgICAgZWxzZWlmICgkbG93IC1tYXRjaCAi0L/QuNGB0YzQvCIpIHsgJGtpbmQgPSAi0J/QuNGB0YzQvNC+IiB9CiAgICAgICAgICAgIGVsc2VpZiAoJGxvdyAtbWF0Y2gg"
	+ "IihefFte0LAt0Y/RkV0p0LTQvtCz0L7QstC+0YB8KF58W17QsC3Rj9GRXSnQtNC+0LNfIikgeyAka2luZCA9ICLQlNC+0LPQvtCy0L7RgCIgfQogICAgICAgICAgICBlbHNlaWYgKCRsb3cgLW1hdGNoICLQsNC60YIiKSB7ICRraW5kID0g"
	+ "ItCQ0LrRgiIgfQoKICAgICAgICAgICAgaWYgKCRraW5kIC1lcSAi0KHRh9C10YIiIC1vciAka2luZCAtZXEgItCj0J/QlCIgLW9yICRraW5kIC1lcSAi0JDQutGCIikgewogICAgICAgICAgICAgICAgaWYgKC1ub3QgJGxvdy5FbmRzV2l0"
	+ "aCgiLnBkZiIpKSB7CiAgICAgICAgICAgICAgICAgICAgJGRvY3MuQWRkKFtwc2N1c3RvbW9iamVjdF1AeyDQktC40LQgPSAi0J/RgNC+0YfQtdC1Ijsg0JjQvNGP0KTQsNC50LvQsCA9ICRsZWFmOyDQn9Cw0LrQtdGCID0gJHBhY2tldDsg"
	+ "0JjQndCd0J/QsNC/0LrQuCA9ICRmb2xkZXJJbm47INCf0YDQuNGH0LjQvdCwID0gItCk0LDQudC7INC90LUgUERGLCDQsiDRg9GH0LXRgiDQvdC1INC/0YDQvtCy0L7QtNC40YLRgdGPLiIgfSkKICAgICAgICAgICAgICAgICAgICBjb250"
	+ "aW51ZQogICAgICAgICAgICAgICAgfQogICAgICAgICAgICAgICAgdHJ5IHsKICAgICAgICAgICAgICAgICAgICAkcGFyc2VkID0gUmVhZC1QZGZKc29uICR0YXJnZXQgJGxlYWYKICAgICAgICAgICAgICAgIH0gY2F0Y2ggewogICAgICAg"
	+ "ICAgICAgICAgICAgICRwYXJzZWQgPSAkbnVsbAogICAgICAgICAgICAgICAgfQogICAgICAgICAgICAgICAgaWYgKCRudWxsIC1lcSAkcGFyc2VkKSB7CiAgICAgICAgICAgICAgICAgICAgJGRvY3MuQWRkKFtwc2N1c3RvbW9iamVjdF1A"
	+ "eyDQktC40LQgPSAi0J/RgNC+0YfQtdC1Ijsg0JjQvNGP0KTQsNC50LvQsCA9ICRsZWFmOyDQn9Cw0LrQtdGCID0gJHBhY2tldDsg0J/RgNC40YfQuNC90LAgPSAiUERGINC90LUg0YDQsNC30L7QsdGA0LDQvS4iIH0pCiAgICAgICAgICAg"
	+ "ICAgICAgICAgY29udGludWUKICAgICAgICAgICAgICAgIH0KICAgICAgICAgICAgICAgICRwYXJzZWQgfCBBZGQtTWVtYmVyIC1Ob3RlUHJvcGVydHlOYW1lINCY0YHRgtC+0YfQvdC40LogLU5vdGVQcm9wZXJ0eVZhbHVlICJQREYiIC1G"
	+ "b3JjZQogICAgICAgICAgICAgICAgJHBhcnNlZCB8IEFkZC1NZW1iZXIgLU5vdGVQcm9wZXJ0eU5hbWUg0J/QsNC60LXRgiAtTm90ZVByb3BlcnR5VmFsdWUgJHBhY2tldCAtRm9yY2UKICAgICAgICAgICAgICAgICRwYXJzZWQgfCBBZGQt"
	+ "TWVtYmVyIC1Ob3RlUHJvcGVydHlOYW1lINCY0J3QndCf0LDQv9C60LggLU5vdGVQcm9wZXJ0eVZhbHVlICRmb2xkZXJJbm4gLUZvcmNlCiAgICAgICAgICAgICAgICAkcGFyc2VkIHwgQWRkLU1lbWJlciAtTm90ZVByb3BlcnR5TmFtZSDQ"
	+ "mNC80Y/QpNCw0LnQu9CwIC1Ob3RlUHJvcGVydHlWYWx1ZSAkbGVhZiAtRm9yY2UKICAgICAgICAgICAgICAgICRwYXJzZWQgfCBBZGQtTWVtYmVyIC1Ob3RlUHJvcGVydHlOYW1lINCY0LQgLU5vdGVQcm9wZXJ0eVZhbHVlICIiIC1Gb3Jj"
	+ "ZQogICAgICAgICAgICAgICAgJHBhcnNlZCB8IEFkZC1NZW1iZXIgLU5vdGVQcm9wZXJ0eU5hbWUg0J/Qu9Cw0YLQtdC20LrQsNCd0L7QvNC10YAgLU5vdGVQcm9wZXJ0eVZhbHVlICIiIC1Gb3JjZQogICAgICAgICAgICAgICAgJHBhcnNl"
	+ "ZCB8IEFkZC1NZW1iZXIgLU5vdGVQcm9wZXJ0eU5hbWUg0J/Qu9Cw0YLQtdC20LrQsNCU0LDRgtCwIC1Ob3RlUHJvcGVydHlWYWx1ZSAiIiAtRm9yY2UKICAgICAgICAgICAgICAgIENvbXBsZXRlLVBhcnNlZCAkcGFyc2VkICRmb2xkZXJJ"
	+ "bm4gJGxlYWYKICAgICAgICAgICAgICAgIGlmICgkcGFyc2VkLtCe0YjQuNCx0LrQsCkgewogICAgICAgICAgICAgICAgICAgICRwYXJzZWQgfCBBZGQtTWVtYmVyIC1Ob3RlUHJvcGVydHlOYW1lINCS0LjQtCAtTm90ZVByb3BlcnR5VmFs"
	+ "dWUgItCf0YDQvtGH0LXQtSIgLUZvcmNlCiAgICAgICAgICAgICAgICAgICAgJHBhcnNlZCB8IEFkZC1NZW1iZXIgLU5vdGVQcm9wZXJ0eU5hbWUg0J/RgNC40YfQuNC90LAgLU5vdGVQcm9wZXJ0eVZhbHVlIChbc3RyaW5nXSRwYXJzZWQu"
	+ "0J7RiNC40LHQutCwKSAtRm9yY2UKICAgICAgICAgICAgICAgIH0gZWxzZWlmICgka2luZCAtZXEgItCQ0LrRgiIgLWFuZCBbc3RyaW5nXSRwYXJzZWQu0JLQuNC0IC1uZSAi0KPQn9CUIiAtYW5kIFtzdHJpbmddJHBhcnNlZC7QktC40LQg"
	+ "LW5lICLQodGH0LXRgiIpIHsKICAgICAgICAgICAgICAgICAgICAkcGFyc2VkIHwgQWRkLU1lbWJlciAtTm90ZVByb3BlcnR5TmFtZSDQktC40LQgLU5vdGVQcm9wZXJ0eVZhbHVlICLQn9GA0L7Rh9C10LUiIC1Gb3JjZQogICAgICAgICAg"
	+ "ICAgICAgICAgICRwYXJzZWQgfCBBZGQtTWVtYmVyIC1Ob3RlUHJvcGVydHlOYW1lINCf0YDQuNGH0LjQvdCwIC1Ob3RlUHJvcGVydHlWYWx1ZSAi0JDQutGCINCx0LXQtyDQo9Cf0JQg0Lgg0YHRh9C10YLQsCwg0LIg0YPRh9C10YIg0L3Q"
	+ "tSDQv9GA0L7QstC+0LTQuNGC0YHRjy4iIC1Gb3JjZQogICAgICAgICAgICAgICAgfQogICAgICAgICAgICAgICAgJGRvY3MuQWRkKCRwYXJzZWQpCiAgICAgICAgICAgICAgICBjb250aW51ZQogICAgICAgICAgICB9CgogICAgICAgICAg"
	+ "ICAkdGl0bGUgPSBbU3lzdGVtLklPLlBhdGhdOjpHZXRGaWxlTmFtZVdpdGhvdXRFeHRlbnNpb24oJGxlYWYpCiAgICAgICAgICAgICRkb2NzLkFkZChbcHNjdXN0b21vYmplY3RdQHsKICAgICAgICAgICAgICAgINCS0LjQtCA9ICRraW5k"
	+ "CiAgICAgICAgICAgICAgICDQmNC80Y/QpNCw0LnQu9CwID0gJGxlYWYKICAgICAgICAgICAgICAgINCd0LDQuNC80LXQvdC+0LLQsNC90LjQtSA9ICR0aXRsZQogICAgICAgICAgICAgICAg0J/QsNC60LXRgiA9ICRwYWNrZXQKICAgICAg"
	+ "ICAgICAgICAgINCY0J3QndCf0LDQv9C60LggPSAkZm9sZGVySW5uCiAgICAgICAgICAgICAgICDQntGB0L3QvtCy0LDQvdC40LUgPSAkdGl0bGUKICAgICAgICAgICAgICAgINCf0YDQuNGH0LjQvdCwID0gJChpZiAoJGtpbmQgLWVxICLQ"
	+ "lNC+0LPQvtCy0L7RgCIpIHsgIiIgfSBlbHNlIHsgItCSINGD0YfQtdGC0L3Ri9C1INC00L7QutGD0LzQtdC90YLRiyDQvdC1INC/0YDQvtCy0L7QtNC40YLRgdGPLiIgfSkKICAgICAgICAgICAgfSkKICAgICAgICAgICAgfSBjYXRjaCB7"
	+ "CiAgICAgICAgICAgICAgICAkZG9jcy5BZGQoW3BzY3VzdG9tb2JqZWN0XUB7INCS0LjQtCA9ICLQn9GA0L7Rh9C10LUiOyDQmNC80Y/QpNCw0LnQu9CwID0gJGxlYWY7INCf0YDQuNGH0LjQvdCwID0gJF8uRXhjZXB0aW9uLk1lc3NhZ2Ug"
	+ "fSkKICAgICAgICAgICAgfQogICAgICAgIH0KICAgIH0gZmluYWxseSB7CiAgICAgICAgJHppcC5EaXNwb3NlKCkKICAgIH0KCiAgICAkZmlsdGVyZWQgPSBOZXctT2JqZWN0IFN5c3RlbS5Db2xsZWN0aW9ucy5HZW5lcmljLkxpc3Rbb2Jq"
	+ "ZWN0XQogICAgZm9yZWFjaCAoJGRvYyBpbiAkZG9jcykgewogICAgICAgIGlmIChbc3RyaW5nXSRkb2Mu0JjRgdGC0L7Rh9C90LjQuiAtZXEgIlBERiIgLWFuZCBbc3RyaW5nXSRkb2Mu0JLQuNC0IC1lcSAi0KPQn9CUIikgewogICAgICAg"
	+ "ICAgICAka2V5ID0gKFtzdHJpbmddJGRvYy7Qn9Cw0LrQtdGCICsgInwiICsgW3N0cmluZ10kZG9jLtCd0L7QvNC10YApLlRvTG93ZXIoKQogICAgICAgICAgICBpZiAoJHhtbEtleXMuQ29udGFpbnNLZXkoJGtleSkpIHsgY29udGludWUg"
	+ "fQogICAgICAgIH0KICAgICAgICAkZmlsdGVyZWQuQWRkKCRkb2MpCiAgICB9CiAgICBXcml0ZS1SZXN1bHQgQHsg0JTQvtC60YPQvNC10L3RgtGLID0gQCgkZmlsdGVyZWQuVG9BcnJheSgpKSB9Cn0gY2F0Y2ggewogICAgV3JpdGUtUmVz"
	+ "dWx0IEB7INCe0YjQuNCx0LrQsCA9ICgi0J3QtSDRg9C00LDQu9C+0YHRjCDQv9GA0L7Rh9C40YLQsNGC0Ywg0LDRgNGF0LjQsiDQlNC40LDQtNC+0LrQsDogIiArICRfLkV4Y2VwdGlvbi5NZXNzYWdlKSB9Cn0gZmluYWxseSB7CiAgICBp"
	+ "ZiAoVGVzdC1QYXRoICR3b3JrKSB7IFJlbW92ZS1JdGVtICR3b3JrIC1SZWN1cnNlIC1Gb3JjZSAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZSB9Cn0K"
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

	Левый = ХвостНомера(НомерДокумента);
	Правый = ХвостНомера(НомерФайла);
	Если Не ЗначениеЗаполнено(Правый) Тогда
		Возврат Ложь;
	КонецЕсли;
	Возврат Левый = Правый;

КонецФункции

Функция ХвостНомера(Номер)

	Текст = СокрЛП(Строка(Номер));
	Хвост = "";
	Пока СтрДлина(Текст) > 0 Цикл
		Символ = Прав(Текст, 1);
		Если Символ < "0" Или Символ > "9" Тогда
			Прервать;
		КонецЕсли;
		Хвост = Символ + Хвост;
		Текст = Лев(Текст, СтрДлина(Текст) - 1);
	КонецЦикла;
	Если Не ЗначениеЗаполнено(Хвост) Тогда
		Хвост = СокрЛП(Строка(Номер));
	КонецЕсли;
	Возврат БезЛидирующихНулей(Хвост);

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
	ЗаписатьСНомером(Счет, Данные.Номер, Неопределено);
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
		ЗаписатьСНомером(Реализация, Данные.Номер, РежимЗаписиДокумента.Проведение);
	Исключение
		ТекстОшибки = КраткоеПредставлениеОшибки(ИнформацияОбОшибке());
		Если СтрНайти(ТекстОшибки, "закрытом периоде") > 0 Тогда
			ВызватьИсключение ТекстОшибки;
		КонецЕсли;
		ЗаписатьСНомером(Реализация, Данные.Номер, РежимЗаписиДокумента.Запись);
		Протокол.Добавить("Реализация записана без проведения: " + ТекстОшибки);
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
		ЗаписатьСНомером(СчетФактура, Данные.Номер, РежимЗаписиДокумента.Проведение);
	Исключение
		ТекстОшибки = КраткоеПредставлениеОшибки(ИнформацияОбОшибке());
		Если СтрНайти(ТекстОшибки, "закрытом периоде") > 0 Тогда
			ВызватьИсключение ТекстОшибки;
		КонецЕсли;
		ЗаписатьСНомером(СчетФактура, Данные.Номер, РежимЗаписиДокумента.Запись);
		Протокол.Добавить("Счет-фактура записан без проведения: " + ТекстОшибки);
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
	Если Не ЗначениеЗаполнено(Контрагент.Наименование) Тогда
		Контрагент.Наименование = "ИНН " + Покупатель.ИНН;
	КонецЕсли;
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

	МожноПроводить = Объект.Метаданные().Проведение = Метаданные.СвойстваОбъектов.Проведение.Разрешить;
	Если Изменения.Количество() = 0 И (Объект.Проведен Или Не МожноПроводить) Тогда
		Возврат "";
	КонецЕсли;

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

	Если Изменения.Количество() = 0 Тогда
		Возврат "проведен, новых реквизитов нет";
	КонецЕсли;
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

Процедура ЗаписатьСНомером(Объект, НомерИзФайла, Режим)

	Попытка
		ЗаписатьОбъект(Объект, Режим);
	Исключение
		Текст = КраткоеПредставлениеОшибки(ИнформацияОбОшибке());
		Если СтрНайти(НРег(Текст), "запрещен") > 0 Тогда
			ВызватьИсключение "пропущен, дата " + Формат(Объект.Дата, "ДЛФ=D") + " в закрытом периоде.";
		КонецЕсли;
		Если СтрНайти(НРег(Текст), "не уникальн") > 0 И ЗначениеЗаполнено(НомерИзФайла) Тогда
			Объект.УстановитьНовыйНомер();
			Если Объект.Метаданные().Реквизиты.Найти("Комментарий") <> Неопределено Тогда
				Объект.Комментарий = СокрЛП(Строка(Объект.Комментарий) + " Номер в файле: " + НомерИзФайла + ".");
			КонецЕсли;
			ЗаписатьОбъект(Объект, Режим);
			Возврат;
		КонецЕсли;
		ВызватьИсключение;
	КонецПопытки;

КонецПроцедуры

Процедура ЗаписатьОбъект(Объект, Режим)

	Если Режим = Неопределено Тогда
		Объект.Записать();
	Иначе
		Объект.Записать(Режим);
	КонецЕсли;

КонецПроцедуры

Функция ДатаИзИмениФайла(ИмяФайла)

	Текст = НРег(СтрЗаменить(Строка(ИмяФайла), "_", " "));
	Позиция = СтрНайти(Текст, " от ");
	Если Позиция = 0 Тогда
		Возврат "";
	КонецЕсли;
	Хвост = СокрЛП(Сред(Текст, Позиция + 4));
	Попытка
		Если СтрДлина(Хвост) >= 8 И Сред(Хвост, 3, 1) = "." И Сред(Хвост, 6, 1) = "." Тогда
			День = Число(Лев(Хвост, 2));
			Месяц = Число(Сред(Хвост, 4, 2));
			ГодТекст = "";
			Для Индекс = 7 По СтрДлина(Хвост) Цикл
				Символ = Сред(Хвост, Индекс, 1);
				Если Символ < "0" Или Символ > "9" Тогда
					Прервать;
				КонецЕсли;
				ГодТекст = ГодТекст + Символ;
			КонецЦикла;
			Год = Число(ГодТекст);
			Если Год < 100 Тогда
				Год = 2000 + Год;
			КонецЕсли;
			Возврат Формат(Дата(Год, Месяц, День), "ДФ=yyyy-MM-dd");
		КонецЕсли;
		ДеньТекст = "";
		Индекс = 1;
		Пока Индекс <= СтрДлина(Хвост) Цикл
			Символ = Сред(Хвост, Индекс, 1);
			Если Символ < "0" Или Символ > "9" Тогда
				Прервать;
			КонецЕсли;
			ДеньТекст = ДеньТекст + Символ;
			Индекс = Индекс + 1;
		КонецЦикла;
		Если Не ЗначениеЗаполнено(ДеньТекст) Тогда
			Возврат "";
		КонецЕсли;
		Месяцы = СтрРазделить("январ,феврал,март,апрел,мая,май,июн,июл,август,сентябр,октябр,ноябр,декабр", ",");
		Номера = СтрРазделить("1,2,3,4,5,5,6,7,8,9,10,11,12", ",");
		Месяц = 0;
		Для Номер = 0 По Месяцы.ВГраница() Цикл
			Если СтрНайти(Хвост, Месяцы[Номер]) > 0 Тогда
				Месяц = Число(Номера[Номер]);
				Прервать;
			КонецЕсли;
		КонецЦикла;
		Год = 0;
		Для Поз = 1 По СтрДлина(Хвост) - 3 Цикл
			Кусок = Сред(Хвост, Поз, 4);
			Если Лев(Кусок, 1) >= "0" И Лев(Кусок, 1) <= "9"
				И Сред(Кусок, 2, 1) >= "0" И Сред(Кусок, 2, 1) <= "9"
				И Сред(Кусок, 3, 1) >= "0" И Сред(Кусок, 3, 1) <= "9"
				И Сред(Кусок, 4, 1) >= "0" И Сред(Кусок, 4, 1) <= "9" Тогда
				Год = Число(Кусок);
				Если Год >= 2000 И Год <= 2099 Тогда
					Прервать;
				КонецЕсли;
				Год = 0;
			КонецЕсли;
		КонецЦикла;
		Если Месяц = 0 Или Год < 2000 Тогда
			Возврат "";
		КонецЕсли;
		Возврат Формат(Дата(Год, Месяц, Число(ДеньТекст)), "ДФ=yyyy-MM-dd");
	Исключение
		Возврат "";
	КонецПопытки;

КонецФункции

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
