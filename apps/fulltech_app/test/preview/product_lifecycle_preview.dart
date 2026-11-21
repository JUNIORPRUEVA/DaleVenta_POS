// Local review entry point. Never imported by main.dart or a release workflow.
import 'package:daleventa_pos/core/auth/token_storage.dart';
import 'package:daleventa_pos/core/models/product_model.dart';
import 'package:daleventa_pos/core/models/user_model.dart';
import 'package:daleventa_pos/core/theme/app_theme.dart';
import 'package:daleventa_pos/features/catalogo/data/catalog_repository.dart';
import 'package:daleventa_pos/features/products/ui/product_lifecycle_dialog.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class _Storage extends TokenStorage {
  _Storage(this.user);
  final UserModel user;
  @override
  Future<UserModel?> getUserSnapshot() async => user;
}
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Uri.base.host != '127.0.0.1' || Uri.base.port != 4492) {
    runApp(const MaterialApp(home: Scaffold(body: Center(child: Text('Solo laboratorio local')))));
    return;
  }
  final fixture=(await Dio().get(Uri.base.resolve('/uat-product-fixture').toString(), options: Options(responseType: ResponseType.json),
    )).data as Map;
  final dio=Dio(BaseOptions(baseUrl:'http://127.0.0.1:4017'));
  final auth=(await dio.post('/auth/login',data:{'email':fixture['email'],'password':fixture['password']})).data as Map;
  final user=UserModel.fromJson(Map<String,dynamic>.from(auth['user'] as Map));
  dio.options.headers['Authorization']='Bearer ${auth['accessToken']}';
  final repo=CatalogRepository(dio,_Storage(user));
  runApp(ProviderScope(overrides:[catalogRepositoryProvider.overrideWithValue(repo)],
    child:MaterialApp(debugShowCheckedModeBanner:false,theme:AppTheme.light,home:const _Preview())));
}
class _Preview extends ConsumerStatefulWidget {
  const _Preview();
  @override
  ConsumerState<_Preview> createState()=>_PreviewState();
}
class _PreviewState extends ConsumerState<_Preview> {
  List<ProductModel> _items=[];
  String? _error;
  @override
  void initState(){super.initState();_load();}
  Future<void> _load() async {
    try {
      final items=await ref.read(catalogRepositoryProvider).fetchProductsFirstPage(forceRefresh:true);
      if(mounted)setState(()=>_items=items);
    }catch(_){if(mounted)setState(()=>_error='No se pudo consultar la API local.');}
  }
  @override
  Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Productos · Laboratorio local')),
    body:Center(child:ConstrainedBox(constraints:const BoxConstraints(maxWidth:920),child:Card(
      child:Padding(padding:const EdgeInsets.all(16),child:Column(children:[
        Row(children:[const Expanded(child:Text('Datos sintéticos · API 4017')),OutlinedButton.icon(
          style:OutlinedButton.styleFrom(shape:const RoundedRectangleBorder()),
          onPressed:()=>showDialog<void>(context:context,builder:(_)=>ArchivedProductsDialog(onChanged:_load)),
          icon:const Icon(Icons.archive_outlined),label:const Text('Archivados'))]),
        if(_error!=null)Text(_error!),
        Expanded(child:ListView.separated(itemCount:_items.length,separatorBuilder:(_,_)=>const Divider(height:1),itemBuilder:(context,index){
          final product=_items[index];return ListTile(dense:true,title:Text(product.nombre),subtitle:Text('Existencias: ${product.stock}'),
            trailing:const Icon(Icons.chevron_right),onTap:()=>showDialog<void>(context:context,builder:(_)=>ProductLifecycleDialog(
              productId:product.id,name:product.nombre,onChanged:_load)));
        })),
      ])),
    ))));
}
