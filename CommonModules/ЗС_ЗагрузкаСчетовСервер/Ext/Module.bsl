
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
			Протокол.Добавить("Счет уже есть, новый не создан: " + Строка(СуществующийСчет));
		Иначе
			СчетСсылка = СоздатьСчет(Данные, ДатаДок, Организация, Контрагент, Договор, Валюта, БанковскийСчет, Ставка, Комментарий);
			Протокол.Добавить("Счет на оплату покупателю: " + Строка(СчетСсылка));
		КонецЕсли;
	КонецЕсли;

	Если СоздаватьУПД Тогда
		СуществующаяРеализация = НайтиСуществующий("РеализацияТоваровУслуг", Данные.Номер, ДатаДок, Контрагент);
		Если ЗначениеЗаполнено(СуществующаяРеализация) Тогда
			Протокол.Добавить("УПД уже есть, новый не создан: " + Строка(СуществующаяРеализация));
		Иначе
			Реализация = СоздатьРеализацию(Данные, ДатаДок, Организация, Контрагент, Договор, Валюта, БанковскийСчет, СчетСсылка, Ставка, Комментарий, Протокол);
			СчетФактура = СоздатьСчетФактуру(Данные, ДатаДок, Организация, Контрагент, Договор, Реализация, Протокол);
			Протокол.Добавить("УПД (реализация): " + Строка(Реализация));
			Протокол.Добавить("Счет-фактура выданный: " + Строка(СчетФактура));
		КонецЕсли;
	КонецЕсли;

	Возврат СтрСоединить(Протокол, Символы.ПС);

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
		УдалитьФайлы(ПутьPDF);
		УдалитьФайлы(ПутьPS);
		УдалитьФайлы(ПутьJSON);
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
	УстановитьЕслиЕсть(Объект, "БанковскийСчет", БанковскийСчет);
	УстановитьЕслиЕсть(Объект, "БанковскийСчетОрганизации", БанковскийСчет);
	УстановитьЕслиЕсть(Объект, "СчетОрганизации", БанковскийСчет);

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
