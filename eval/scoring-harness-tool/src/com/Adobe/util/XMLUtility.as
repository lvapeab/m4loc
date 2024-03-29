//////////////////////////////////////////////////////////////////////////////////////
//
//    Copyright 2012 Adobe Systems Incorporated
//
//    This file is part of TMX to Moses Corpus Tool.
// 
//    TMX to Moses Corpus Tool is free software: you can redistribute it and/or modify
//    it under the terms of the GNU Lesser General Public License as published by the 
//    Free Software Foundation, either version 3 of the License, or (at your option) 
//    any later version.
// 
//    TMX to Moses Corpus Tool is distributed in the hope that it will be useful,
//    but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY 
//    or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for 
//    more details.
// 
//    You should have received a copy of the GNU Lesser General Public License along 
//    with TMX to Moses Corpus Tool.  If not, see <http://www.gnu.org/licenses/>.
//
//////////////////////////////////////////////////////////////////////////////////////


package com.Adobe.util
{
	import mx.collections.XMLListCollection;

	public class XMLUtility
	{
		public function XMLUtility()
		{
		}
		
		public function XMLList2Array(xmlList:XMLList):Array{
			
			var list:Array = new Array();
			
			for each (var item:XML in xmlList){
				
				list.push(item.toString());
			}
			
//			list.sort(Array.CASEINSENSITIVE);
			
			function removeDupAndEmpty(item:Object, index:uint, arr:Array):Boolean {
				
				return arr.indexOf(item) == index && item.toString() != "";
			}
			
			return list.filter(removeDupAndEmpty);
		}
				
	}
}